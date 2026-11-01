import AppKit
import Observation
import ReefCore
@preconcurrency import UserNotifications

/// Owns every piece of live state: sessions, the notch machine, pending requests and the socket server.
@MainActor @Observable
final class AppState {
    var sessionState = SessionState()
    var notch: NotchMachine
    var revealedKeys: Set<SessionKey> = []
    var settings: ReefSettings {
        didSet {
            guard settings != oldValue else { return }
            notch.timing = settings.notchTiming
            try? settings.save(to: Paths.settingsFile)
            if settings.watchCodexTranscripts != oldValue.watchCodexTranscripts { syncCodexWatcher() }
            onSettingsChanged?()
        }
    }
    @ObservationIgnored var onSettingsChanged: (() -> Void)?
    /// Mirrors the system's "reduce motion" setting; stepped animation freezes when it is on.
    var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    /// Drives the staged content fade. Set false the instant the panel starts growing and true
    /// immediately after, so the header and rows fade in behind the growing frame (M3, M4).
    var contentRevealed = false
    /// Claude Code's rate limits, when the status-line shim is feeding them.
    var usage: UsageSnapshot?
    /// Codex account limits recovered from recent rollout transcript token-count records.
    var codexUsage: UsageSnapshot?
    @ObservationIgnored private var usageReader: UsageReader?
    @ObservationIgnored private var codexUsageReader: CodexUsageReader?
    @ObservationIgnored private var codexWatcher: CodexTranscriptWatcher?
    @ObservationIgnored let sounds = SoundPlayer()
    @ObservationIgnored private let barkClient = BarkClient()
    @ObservationIgnored private var isLoadingBarkCredential = false
    var barkDeviceKey = "" {
        didSet {
            guard barkDeviceKey != oldValue, !isLoadingBarkCredential else { return }
            if !BarkCredentialStore.save(barkDeviceKey) {
                barkStatus = "Could not save the device key in Keychain."
            }
        }
    }
    var barkStatus: String?
    var barkTestInProgress = false

    /// Keychain may present an authorization prompt after an ad-hoc development rebuild. Never
    /// let that synchronous Security call block applicationDidFinishLaunching, the socket, or
    /// the notch. A production-signed update normally completes this without showing anything.
    func loadBarkCredential() {
        Task { [weak self] in
            let stored = await Task.detached(priority: .userInitiated) {
                BarkCredentialStore.load()
            }.value
            guard let self, self.barkDeviceKey.isEmpty, !stored.isEmpty else { return }
            self.isLoadingBarkCredential = true
            self.barkDeviceKey = stored
            self.isLoadingBarkCredential = false
        }
    }

    var muted: Bool { get { settings.muted } set { settings.muted = newValue } }
    var showHeadless: Bool { settings.showHeadless }
    var showProject: Bool { settings.showProject }
    var showBranch: Bool { settings.showBranch }
    var showSubagents: Bool { settings.showSubagents }
    var idleCleanup: TimeInterval { settings.idleCleanupHours * 3600 }

    func avatarEmotion(for slot: AvatarStatusSlot) -> AvatarEmotion {
        settings.avatarEmotionByStatus[slot.rawValue]
            .flatMap(AvatarEmotion.init(rawValue:)) ?? slot.defaultEmotion
    }

    func setAvatarEmotion(_ emotion: AvatarEmotion, for slot: AvatarStatusSlot) {
        settings.avatarEmotionByStatus[slot.rawValue] = emotion.rawValue
    }

    @ObservationIgnored let pending = PendingRequests()
    @ObservationIgnored let jumpEngine = JumpEngine()
    @ObservationIgnored let frontmost = FrontmostTracker()
    @ObservationIgnored let terminals = SessionTerminalsStore(url: Paths.sessionTerminalsFile)
    @ObservationIgnored private let server: UnixSocketServer
    @ObservationIgnored private let serverQueue = DispatchQueue(label: "app.reef.socket")
    @ObservationIgnored private var deadlineTimer: Timer?
    @ObservationIgnored private var housekeepingTimer: Timer?
    @ObservationIgnored private var processMonitor: ProcessLivenessMonitor?
    @ObservationIgnored private var socketRetryTimer: Timer?
    @ObservationIgnored var onStateChanged: (() -> Void)?

    static func waitDeadline(for source: AgentSource) -> TimeInterval {
        source == .claude ? 86_400 : 3_600
    }

    init() {
        let loaded = ReefSettings.load(from: Paths.settingsFile)
        settings = loaded
        notch = NotchMachine(timing: loaded.notchTiming)
        server = UnixSocketServer(path: Paths.socketPath, queue: serverQueue)
        server.onRequest = { [weak self] request, connection in
            DispatchQueue.main.async { self?.handle(request: request, connection: connection) }
        }
        pending.onDropped = { [weak self] requestID in self?.requestDropped(requestID) }
        frontmost.onActivation = { [weak self] _ in self?.releaseRequestsForFrontmostTerminal() }
    }

    // MARK: - Lifecycle

    func start(backgroundServices: Bool = true) {
        guard backgroundServices else { return }
        startSocketServer()
        housekeepingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.housekeeping() }
        }
        let reader = UsageReader { [weak self] snapshot in self?.usage = snapshot }
        reader.start()
        usageReader = reader
        let codexReader = CodexUsageReader(root: Paths.codexSessions) { [weak self] snapshot in
            self?.codexUsage = snapshot
        }
        codexReader.start()
        codexUsageReader = codexReader
        syncCodexWatcher()
        let monitor = ProcessLivenessMonitor(hasActiveSessions: { [weak self] in
            self?.sessions.isEmpty == false
        }, onSnapshot: { [weak self] sources in
            guard let self else { return }
            self.apply(SessionReducer.reconcileProcessLiveness(&self.sessionState,
                                                               aliveProcessIDs: sources.processIDs,
                                                               aliveSources: sources.sources, now: Date()))
        })
        monitor.start()
        processMonitor = monitor
    }

    /// A rebuild briefly overlaps the outgoing and incoming app processes. If the old listener
    /// still owns the hook socket, keep retrying until shutdown releases it instead of leaving
    /// the new Reef instance permanently blind to agent events.
    private func startSocketServer() {
        do {
            try server.start()
            socketRetryTimer?.invalidate()
            socketRetryTimer = nil
            Log.info("socket", "listening", ["path": Paths.socketPath])
        } catch {
            Log.warn("socket", "failed to listen", ["path": Paths.socketPath, "error": "\(error)"])
            guard socketRetryTimer == nil else { return }
            socketRetryTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.startSocketServer() }
            }
        }
    }

    /// Starts or stops transcript watching to match the setting, clearing watched sessions when
    /// it is turned off so the island reflects the choice immediately.
    func syncCodexWatcher() {
        if settings.watchCodexTranscripts {
            guard codexWatcher == nil else { return }
            let watcher = CodexTranscriptWatcher(root: Paths.codexSessions) { [weak self] transcript in
                self?.applyWatched(transcript)
            }
            watcher.start()
            codexWatcher = watcher
        } else {
            codexWatcher?.stop()
            codexWatcher = nil
            apply(SessionReducer.removeWatched(&sessionState))
        }
    }

    private func applyWatched(_ transcript: TranscriptSession) {
        let key = SessionKey(source: .codex, sessionID: transcript.id)
        let isNew = sessionState.sessions[key] == nil
        apply(SessionReducer.upsertWatched(&sessionState, transcript, key: key, now: Date()))
        if isNew, sessionState.sessions[key]?.ingress == .transcript {
            Log.info("codex", "watched session", ["id": transcript.id, "project": sessionState.sessions[key]?.project ?? "-"])
        }
    }

    func stop() {
        socketRetryTimer?.invalidate()
        socketRetryTimer = nil
        codexWatcher?.stop()
        usageReader?.stop()
        codexUsageReader?.stop()
        processMonitor?.stop()
        pending.releaseAll()
        server.stop()
        deadlineTimer?.invalidate()
        housekeepingTimer?.invalidate()
    }

    // MARK: - Derived

    var sessions: [Session] { sessionState.ordered }

    var visibleSessions: [Session] {
        sessions.filter { showHeadless || !$0.terminal.isHeadless }
    }

    var pendingRequests: [(session: Session, request: PendingRequest)] {
        visibleSessions.flatMap { session in session.pending.map { (session, $0) } }
            .sorted { $0.request.receivedAt < $1.request.receivedAt }
    }

    var livePendingCount: Int { visibleSessions.flatMap(\.pending).filter(\.isLive).count }

    // MARK: - Ingress

    func handle(request: BridgeRequest, connection: UnixSocketServer.Connection) {
        guard let sourceRaw = request.event["source"] as? String, let source = AgentSource(rawValue: sourceRaw),
              let event = try? HookEvent(source: source, json: request.event)
        else {
            Log.warn("socket", "unparseable request", ["id": request.id, "mode": request.mode.rawValue])
            if request.mode == .wait { connection.reply(BridgeResponse(id: request.id, reply: [:])) }
            return
        }
        let key = SessionKey(source: source, sessionID: event.sessionID)
        let requestID: String? = request.mode == .wait ? request.id : nil
        let normalized = AgentEventAdapter.normalize(event)
        if sessionState.dismissedKeys.contains(key) {
            // Closing a live card hands any later blocking prompt back to its terminal instead
            // of leaving the bridge waiting forever. SessionEnd clears the suppression key.
            if normalized.kind == .sessionEnded {
                _ = SessionReducer.reduce(&sessionState, event: normalized, requestID: nil, now: Date())
            }
            if request.mode == .wait {
                connection.reply(BridgeResponse(id: request.id, reply: [:]))
            }
            Log.info("session", "ignored dismissed", ["session": String(event.sessionID.prefix(8))])
            return
        }
        if request.mode == .wait {
            pending.add(requestID: request.id, key: key, connection: connection,
                        deadline: Date().addingTimeInterval(Self.waitDeadline(for: source)))
        }
        Log.info("session", "recv", ["event": event.name, "source": sourceRaw, "session": String(event.sessionID.prefix(8)),
                                     "tool": event.toolName ?? ""])
        let effects = SessionReducer.reduce(&sessionState, event: normalized, requestID: requestID, now: Date())
        rememberTerminal(for: key)
        apply(effects)
    }

    /// Persist a known terminal; restore one for sessions whose events carried no identity.
    private func rememberTerminal(for key: SessionKey) {
        guard var session = sessionState.sessions[key] else { return }
        if session.terminal.isHeadless, let stored = terminals.identity(for: key) {
            session.terminal = stored
            sessionState.sessions[key] = session
        } else {
            terminals.remember(session.terminal, for: key)
        }
    }

    /// Approvals follow focus: a request whose terminal is frontmost goes back to the terminal prompt.
    private func releaseRequestsForFrontmostTerminal() {
        var changed = false
        for entry in pendingRequests where entry.request.isLive && frontmost.isFrontmost(entry.session.terminal) {
            releaseToTerminal(requestID: entry.request.requestID, key: entry.session.key)
            changed = true
        }
        if changed {
            syncPendingCount()
            notch.apply(.requestsCleared(Date()))
            stateDidChange()
        }
    }

    private func releaseToTerminal(requestID: String, key: SessionKey) {
        pending.release(requestID: requestID)
        // Once ownership returns to the editor/terminal, Reef can no longer answer this
        // request. Keeping a read-only copy made one agent accumulate a card for every command.
        // Remove it from the session; the normal session card still represents the agent.
        apply(SessionReducer.clearRequest(&sessionState, key: key, requestID: requestID))
        Log.info("session", "request released to terminal", ["request": requestID])
    }

    private func requestDropped(_ requestID: String) {
        for session in sessions where session.pending.contains(where: { $0.requestID == requestID }) {
            apply(SessionReducer.clearRequest(&sessionState, key: session.key, requestID: requestID))
        }
        Log.info("session", "request dropped by peer", ["request": requestID])
    }

    // MARK: - Effects

    private func apply(_ effects: [SessionEffect]) {
        let now = Date()
        for effect in effects {
            switch effect {
            case let .requestArrived(key, request):
                guard let session = sessionState.sessions[key], showHeadless || !session.terminal.isHeadless else {
                    pending.release(requestID: request.requestID)
                    continue
                }
                if frontmost.isFrontmost(session.terminal) {
                    // The user is already looking at that terminal: hand the prompt back and only peek the card.
                    releaseToTerminal(requestID: request.requestID, key: key)
                    syncPendingCount()
                    if notch.state == .closed || isTransientNotch {
                        notch.apply(.present(.sessionList(actionableRequestID: request.requestID),
                                             reason: .completion, at: now))
                    }
                } else {
                    sendBark(kind: .inputNeeded, session: session, request: request)
                    syncPendingCount()
                    let surface: ReefSurface
                    switch request.kind {
                    case .permission: surface = .approval(requestID: request.requestID)
                    case .question: surface = .question(requestID: request.requestID)
                    case .plan: surface = .plan(requestID: request.requestID)
                    }
                    notch.apply(.present(surface, reason: .blockingRequest, at: now))
                }
            case let .requestCleared(_, requestID):
                pending.release(requestID: requestID)
                syncPendingCount()
                notch.apply(.requestsCleared(now))
                if let next = pendingRequests.first(where: { $0.request.isLive }) {
                    let surface: ReefSurface
                    switch next.request.kind {
                    case .permission: surface = .approval(requestID: next.request.requestID)
                    case .question: surface = .question(requestID: next.request.requestID)
                    case .plan: surface = .plan(requestID: next.request.requestID)
                    }
                    notch.apply(.present(surface, reason: .blockingRequest, at: now))
                }
            case let .revealCompletion(key):
                revealedKeys.insert(key)
                if let session = sessionState.sessions[key] { sendBark(kind: .done, session: session) }
                schedulePeek { [weak self] in
                    guard let self, self.notch.state == .closed || self.isTransientNotch else { return }
                    self.notch.apply(.present(.completion(key), reason: .completion, at: Date()))
                }
                notifyIfAllFinished()
            case let .revealFailure(key):
                revealedKeys.insert(key)
                if let session = sessionState.sessions[key] { sendBark(kind: .failed, session: session) }
                schedulePeek { [weak self] in
                    guard let self, self.notch.state == .closed || self.isTransientNotch else { return }
                    self.notch.apply(.present(.failure(key), reason: .failure, at: Date()))
                }
            case let .sound(kind):
                let enabled = settings.soundEnabled(kind)
                Log.info("sound", kind.rawValue, ["played": enabled ? "1" : "0"])
                if enabled { sounds.play(kind) }
            case let .removed(key):
                revealedKeys.remove(key)
                terminals.forget(key)
                pending.releaseAll(for: key)
                syncPendingCount()
                notch.apply(.requestsCleared(now))
            }
        }
        stateDidChange()
    }

    /// "All agents finished": a macOS notification once no visible session is still working. Needs a bundle id.
    private func notifyIfAllFinished() {
        guard settings.notifyAllFinished, Bundle.main.bundleIdentifier != nil else { return }
        let busy = visibleSessions.contains { session in
            switch session.status {
            case .working, .runningTool, .compacting: return true
            default: return session.status.isWaitingOnUser
            }
        }
        guard !busy else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "All agents finished"
            content.body = "No agent is working anymore."
            center.add(UNNotificationRequest(identifier: "reef.all-finished", content: content, trigger: nil))
        }
    }

    // MARK: - Bark

    var barkIsConfigured: Bool {
        !barkDeviceKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (try? BarkClient.request(configuration: barkConfiguration,
                                        message: BarkMessage(title: "Reef", body: "Validation"))) != nil
    }

    func testBark() {
        guard !barkTestInProgress else { return }
        barkTestInProgress = true
        barkStatus = "Sending…"
        let configuration = barkConfiguration
        let message = BarkMessage(title: "Reef test",
                                  body: "Bark notifications are connected to this Mac.",
                                  level: settings.barkNotificationLevel,
                                  sound: settings.barkSound)
        Task { [weak self, barkClient] in
            do {
                try await barkClient.send(configuration: configuration, message: message)
                guard let self else { return }
                self.barkStatus = "Sent to your iPhone."
                Log.info("bark", "test sent")
            } catch {
                guard let self else { return }
                self.barkStatus = error.localizedDescription
                Log.warn("bark", "test failed", ["error": error.localizedDescription])
            }
            self?.barkTestInProgress = false
        }
    }

    private var barkConfiguration: BarkConfiguration {
        BarkConfiguration(serverURL: settings.barkServerURL, deviceKey: barkDeviceKey)
    }

    private func sendBark(kind: SoundKind, session: Session, request: PendingRequest? = nil) {
        guard settings.barkEnabled(kind), barkIsConfigured else { return }
        let subject = session.project ?? (session.key.source == .claude ? "Claude" : "Codex")
        let title: String
        var body: String
        let level: BarkNotificationLevel
        switch kind {
        case .started, .actionCompleted:
            return
        case .inputNeeded:
            title = "Reef · Input needed"
            level = settings.barkNotificationLevel
            switch request?.kind {
            case .question: body = "\(subject) has a question for you."
            case .plan: body = "\(subject) has a plan ready for review."
            case .permission:
                let tool = request?.event.toolName ?? "a tool"
                body = "\(subject) needs approval for \(tool)."
            case .none: body = "\(subject) needs your input."
            }
        case .done:
            title = "Reef · Agent finished"
            body = "\(subject) finished its turn."
            level = settings.barkNotificationLevel
        case .failed:
            title = "Reef · Agent failed"
            body = "\(subject) ended with an error."
            level = settings.barkNotificationLevel
        }
        let configuration = barkConfiguration
        let message = BarkMessage(title: title, body: body, level: level, sound: settings.barkSound)
        Task { [barkClient] in
            do {
                try await barkClient.send(configuration: configuration, message: message)
                Log.info("bark", "notification sent", ["kind": kind.rawValue])
            } catch {
                Log.warn("bark", "notification failed", ["kind": kind.rawValue,
                                                           "error": error.localizedDescription])
            }
        }
    }

    /// A completion peek opens a beat after the panel settles rather than the instant the turn
    /// ends (M8), so finishing reads as a separate event instead of a jump.
    @ObservationIgnored private var peekWorkItem: DispatchWorkItem?

    private func schedulePeek(_ body: @escaping () -> Void) {
        peekWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            body()
            self?.stateDidChange()
        }
        peekWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Motion.peekDelay, execute: item)
    }

    private func syncPendingCount() {
        notch.pendingCount = livePendingCount
    }

    // MARK: - User intents

    func hover(inside: Bool) {
        let now = Date()
        if inside, !settings.hoverExpand, notch.state == .closed { return }
        notch.apply(inside ? .hoverEnter(now) : .hoverExit(now))
        stateDidChange()
    }

    func surfaceEntered() {
        notch.apply(.surfaceEntered(Date()))
    }

    func click() { notch.apply(.click(Date())); stateDidChange() }
    func outsideClick() { notch.apply(.outsideClick(Date())); stateDidChange() }
    func escape() { notch.apply(.escape(Date())); stateDidChange() }

    private var isTransientNotch: Bool {
        if case .transient = notch.state { return true }
        return false
    }

    /// Presentations are computed once per request (diffs can be large), never per render.
    @ObservationIgnored private var presentations: [String: ApprovalPresentation] = [:]

    func presentation(for request: PendingRequest, in session: Session) -> ApprovalPresentation {
        if let cached = presentations[request.requestID] { return cached }
        let made = ApprovalPresentation.make(toolName: request.event.toolName ?? "tool", toolInput: request.event.toolInput ?? [:],
                                             source: session.key.source, readFile: readFile)
        presentations[request.requestID] = made
        return made
    }

    func decide(requestID: String, decision: Decision) {
        guard let entry = pendingRequests.first(where: { $0.request.requestID == requestID }) else { return }
        let resolved = pending.resolve(requestID: requestID, decision: decision, source: entry.session.key.source)
        Log.info("session", "decision", ["request": requestID, "resolved": resolved ? "1" : "0"])
        questionSelections[requestID] = nil
        presentations[requestID] = nil
        apply(SessionReducer.clearRequest(&sessionState, key: entry.session.key, requestID: requestID))
    }

    func alwaysAllow(requestID: String) {
        guard let entry = pendingRequests.first(where: { $0.request.requestID == requestID }) else { return }
        let event = entry.request.event
        let always = AlwaysAllow(toolName: event.toolName ?? "", suggestion: event.permissionSuggestions?.first)
        decide(requestID: requestID, decision: .allow(alwaysAllow: always))
    }

    // MARK: Questions and plans

    var questionSelections: [String: QuestionSelection] = [:]

    func selection(for requestID: String, questions: [Question]) -> QuestionSelection {
        questionSelections[requestID] ?? QuestionSelection(questions: questions)
    }

    func updateSelection(for requestID: String, questions: [Question], _ change: (inout QuestionSelection) -> Void) {
        var current = selection(for: requestID, questions: questions)
        change(&current)
        questionSelections[requestID] = current
    }

    func answerQuestion(requestID: String) {
        guard let entry = pendingRequests.first(where: { $0.request.requestID == requestID }) else { return }
        let input = entry.request.event.toolInput ?? [:]
        let questions = QuestionAnswer.parse(toolInput: input)
        let current = selection(for: requestID, questions: questions)
        guard current.canSubmit else { return }
        decide(requestID: requestID, decision: .allow(updatedInput: QuestionAnswer.updatedInput(original: input, answers: current.answers())))
    }

    func answerPlan(requestID: String, approve: Bool, feedback: String) {
        guard let entry = pendingRequests.first(where: { $0.request.requestID == requestID }) else { return }
        let input = entry.request.event.toolInput ?? [:]
        if approve {
            decide(requestID: requestID, decision: .allow(updatedInput: PlanAnswer.updatedInput(original: input)))
        } else {
            decide(requestID: requestID, decision: .deny(message: feedback.isEmpty ? "Plan rejected from Reef" : feedback))
        }
    }

    // MARK: Shortcuts, jump, settings

    func perform(_ shortcut: PanelShortcut) {
        let oldest = pendingRequests.first(where: { $0.request.isLive })
        switch shortcut {
        case .collapse: escape()
        case .allow:
            guard let oldest else { return }
            if oldest.request.kind == .plan { answerPlan(requestID: oldest.request.requestID, approve: true, feedback: "") }
            else if oldest.request.kind == .permission { decide(requestID: oldest.request.requestID, decision: .allow()) }
        case .deny:
            guard let oldest, oldest.request.kind != .question else { return }
            decide(requestID: oldest.request.requestID, decision: .deny(message: "Denied from Reef"))
        case .alwaysAllow:
            guard let oldest, oldest.request.kind == .permission, oldest.session.key.source == .claude else { return }
            alwaysAllow(requestID: oldest.request.requestID)
        case .submit:
            guard let oldest, oldest.request.kind == .question else { return }
            answerQuestion(requestID: oldest.request.requestID)
        case .jump:
            if let session = oldest?.session ?? visibleSessions.first { jump(session: session) }
        }
    }

    func jump(session: Session) {
        let steps = JumpPlanner.plan(session.terminal, cwd: session.cwd)
        Log.info("jump", "requested", ["session": String(session.key.sessionID.prefix(8)), "steps": "\(steps.count)"])
        guard !steps.isEmpty else { return }
        notch.apply(.escape(Date()))
        stateDidChange()
        Task { await jumpEngine.run(steps) }
    }

    func dismiss(session: Session) {
        dismissSessions([session.key], reason: "user")
    }

    func dismissInactiveSessions() {
        let keys = sessions.filter { session in
            session.pending.isEmpty && [.idle, .done, .failed].contains(session.status)
        }.map(\.key)
        dismissSessions(keys, reason: "inactive")
    }

    func dismissAllSessions() {
        dismissSessions(sessions.map(\.key), reason: "all")
    }

    private func dismissSessions(_ keys: [SessionKey], reason: String) {
        let existing = keys.filter { sessionState.sessions[$0] != nil }
        guard !existing.isEmpty else { return }
        Log.info("session", "dismissed", ["count": "\(existing.count)", "reason": reason])
        apply(existing.flatMap { SessionReducer.dismiss(&sessionState, key: $0) })
    }

    @ObservationIgnored var onOpenSettings: (() -> Void)?
    var notice: String?

    func openSettings() {
        Log.info("ui", "settings requested")
        onOpenSettings?()
    }

    func showNotice(_ text: String) {
        notice = text
        stateDidChange()
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if self?.notice == text { self?.notice = nil; self?.stateDidChange() }
        }
    }

    // MARK: Hooks

    var installedHookSources: [AgentSource] {
        AgentSource.allCases.filter { settings.hookIntent(for: $0) == .installed }
    }

    func installHooks(_ source: AgentSource) -> String? {
        if let error = HookInstaller.install(source) { return error }
        if !settings.hooksInstalledByUser.contains(source.rawValue) { settings.hooksInstalledByUser.append(source.rawValue) }
        settings.hookIntentBySource[source.rawValue] = HookIntent.installed.rawValue
        return nil
    }

    func uninstallHooks(_ source: AgentSource) -> String? {
        if let error = HookInstaller.uninstall(source) { return error }
        settings.hooksInstalledByUser.removeAll { $0 == source.rawValue }
        settings.hookIntentBySource[source.rawValue] = HookIntent.uninstalled.rawValue
        return nil
    }

    func readFile(_ path: String) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int, size < 1_000_000 else { return nil }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    // MARK: - Deterministic interaction harness

    /// Seeds the real reducer and UI without requiring Accessibility-driven synthetic input.
    /// Used by scripts/harness.sh for repeatable screenshots and smoke runs.
    func loadHarnessScenario(_ name: String) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func event(_ eventName: String, tool: String? = nil, extra: [String: Any] = [:]) -> HookEvent? {
            var json: [String: Any] = [
                "hook_event_name": eventName,
                "session_id": "reef-harness-session",
                "cwd": "/tmp/reef-harness",
                "model": "Harness",
                "reef": ["tty": "/dev/ttys999",
                         "env": ["__CFBundleIdentifier": JumpPlanner.terminalBundle]],
            ]
            if let tool { json["tool_name"] = tool }
            for (key, value) in extra { json[key] = value }
            return try? HookEvent(source: .claude, json: json)
        }
        func ingest(_ hook: HookEvent?, requestID: String? = nil) {
            guard let hook else { return }
            apply(SessionReducer.reduce(&sessionState, event: AgentEventAdapter.normalize(hook),
                                        requestID: requestID, now: now))
        }

        ingest(event("SessionStart"))
        switch name {
        case "closed": break
        case "opened":
            ingest(event("UserPromptSubmit", extra: ["prompt": "Implement the interaction harness"] ))
            notch.apply(.click(now))
        case "approval":
            ingest(event("PermissionRequest", tool: "Bash", extra: ["tool_input": ["command": "swift test"]]),
                   requestID: "harness-approval")
        case "question":
            let questions: [[String: Any]] = [["question": "Which display should Reef use?", "header": "Display",
                                               "options": [["label": "Automatic", "description": "Prefer the built-in notch"],
                                                           ["label": "External", "description": "Use the selected monitor"]],
                                               "multiSelect": false]]
            ingest(event("PermissionRequest", tool: "AskUserQuestion", extra: ["tool_input": ["questions": questions]]),
                   requestID: "harness-question")
        case "completion":
            ingest(event("UserPromptSubmit"))
            ingest(event("Stop", extra: ["last_assistant_message": "Implemented and verified the requested changes."]))
            notch.apply(.present(.completion(SessionKey(source: .claude, sessionID: "reef-harness-session")),
                                 reason: .completion, at: now))
        case "failure":
            ingest(event("UserPromptSubmit"))
            ingest(event("StopFailure"))
            notch.apply(.present(.failure(SessionKey(source: .claude, sessionID: "reef-harness-session")),
                                 reason: .failure, at: now))
        default:
            notch.apply(.click(now))
        }
        stateDidChange()
    }

    func harnessSnapshotData(scenario: String) -> Data? {
        func stateName(_ state: NotchState) -> String {
            switch state {
            case .closed: return "closed"
            case .blocking: return "blocking"
            case .manualExpanded: return "manualExpanded"
            case let .transient(kind, _): return "transient.\(kind)"
            }
        }
        func surfaceName(_ surface: ReefSurface) -> String {
            switch surface {
            case .sessionList: return "sessionList"
            case .approval: return "approval"
            case .question: return "question"
            case .plan: return "plan"
            case .completion: return "completion"
            case .failure: return "failure"
            }
        }
        let object: [String: Any] = [
            "scenario": scenario,
            "notchState": stateName(notch.state),
            "openReason": notch.openReason?.rawValue ?? NSNull(),
            "surface": surfaceName(notch.surface),
            "sessionCount": visibleSessions.count,
            "pendingCount": livePendingCount,
            "labels": visibleSessions.map { session in
                ["source": session.key.source.rawValue, "project": session.project ?? "",
                 "waiting": session.status.isWaitingOnUser]
            },
        ]
        return try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }


    // MARK: - Timers

    private func housekeeping() {
        let now = Date()
        let expired = pending.expire(now: now)
        for id in expired {
            for session in sessions where session.pending.contains(where: { $0.requestID == id }) {
                apply(SessionReducer.clearRequest(&sessionState, key: session.key, requestID: id))
            }
            Log.info("session", "request expired", ["request": id])
        }
        if !expired.isEmpty { syncPendingCount(); notch.apply(.requestsCleared(now)) }
        if Int(now.timeIntervalSince1970) % 60 == 0 {
            apply(SessionReducer.pruneIdle(&sessionState, now: now, maxIdle: idleCleanup))
        }
        syncPendingCount()
        stateDidChange()
    }

    private func stateDidChange() {
        syncContentReveal()
        scheduleTick()
        onStateChanged?()
    }

    /// Content is hidden while the panel is collapsed, and revealed one runloop turn after it
    /// starts expanding so the fade has something to animate from.
    private func syncContentReveal() {
        let expanded = notch.state.isExpanded
        if !expanded {
            contentRevealed = false
        } else if !contentRevealed {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.notch.state.isExpanded else { return }
                self.contentRevealed = true
            }
        }
    }

    private func scheduleTick() {
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        guard let deadline = notch.nextDeadline else { return }
        let delay = max(0.01, deadline.timeIntervalSinceNow)
        deadlineTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.notch.apply(.tick(Date()))
                self.stateDidChange()
            }
        }
    }
}
