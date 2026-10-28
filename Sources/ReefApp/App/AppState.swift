import AppKit
import Observation
import ReefCore
import UserNotifications

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
            onSettingsChanged?()
        }
    }
    @ObservationIgnored var onSettingsChanged: (() -> Void)?
    @ObservationIgnored let sounds = SoundPlayer()

    var muted: Bool { get { settings.muted } set { settings.muted = newValue } }
    var showHeadless: Bool { settings.showHeadless }
    var showProject: Bool { settings.showProject }
    var showBranch: Bool { settings.showBranch }
    var showSubagents: Bool { settings.showSubagents }
    var idleCleanup: TimeInterval { settings.idleCleanupHours * 3600 }

    @ObservationIgnored let pending = PendingRequests()
    @ObservationIgnored let jumpEngine = JumpEngine()
    @ObservationIgnored let frontmost = FrontmostTracker()
    @ObservationIgnored let terminals = SessionTerminalsStore(url: Paths.sessionTerminalsFile)
    @ObservationIgnored private let server: UnixSocketServer
    @ObservationIgnored private let serverQueue = DispatchQueue(label: "app.reef.socket")
    @ObservationIgnored private var deadlineTimer: Timer?
    @ObservationIgnored private var housekeepingTimer: Timer?
    @ObservationIgnored var onStateChanged: (() -> Void)?

    static let waitDeadline: TimeInterval = 3600

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

    func start() {
        do {
            try server.start()
            Log.info("socket", "listening", ["path": Paths.socketPath])
        } catch {
            Log.warn("socket", "failed to listen", ["path": Paths.socketPath, "error": "\(error)"])
        }
        housekeepingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.housekeeping() }
        }
    }

    func stop() {
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
        if request.mode == .wait {
            pending.add(requestID: request.id, key: key, connection: connection,
                        deadline: Date().addingTimeInterval(Self.waitDeadline))
        }
        Log.info("session", "recv", ["event": event.name, "source": sourceRaw, "session": String(event.sessionID.prefix(8)),
                                     "tool": event.toolName ?? ""])
        let effects = SessionReducer.reduce(&sessionState, event: event, requestID: requestID, now: Date())
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
        if changed { syncPendingCount(); stateDidChange() }
    }

    private func releaseToTerminal(requestID: String, key: SessionKey) {
        pending.release(requestID: requestID)
        SessionReducer.markReleased(&sessionState, key: key, requestID: requestID)
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
                    releaseToTerminal(requestID: request.requestID, key: key)
                }
                syncPendingCount()
                notch.apply(.requestArrived(now))
            case let .requestCleared(_, requestID):
                pending.release(requestID: requestID)
                syncPendingCount()
                notch.apply(.requestsCleared(now))
            case let .revealCompletion(key):
                revealedKeys.insert(key)
                notch.apply(.taskComplete(now))
                notifyIfAllFinished()
            case let .revealFailure(key):
                revealedKeys.insert(key)
                notch.apply(.taskFailed(now))
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

    func click() { notch.apply(.click(Date())); stateDidChange() }
    func outsideClick() { notch.apply(.outsideClick(Date())); stateDidChange() }
    func escape() { notch.apply(.escape(Date())); stateDidChange() }

    func decide(requestID: String, decision: Decision) {
        guard let entry = pendingRequests.first(where: { $0.request.requestID == requestID }) else { return }
        let resolved = pending.resolve(requestID: requestID, decision: decision, source: entry.session.key.source)
        Log.info("session", "decision", ["request": requestID, "resolved": resolved ? "1" : "0"])
        questionSelections[requestID] = nil
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
        settings.hooksInstalledByUser.compactMap(AgentSource.init(rawValue:))
    }

    func installHooks(_ source: AgentSource) -> String? {
        if let error = HookInstaller.install(source) { return error }
        if !settings.hooksInstalledByUser.contains(source.rawValue) { settings.hooksInstalledByUser.append(source.rawValue) }
        return nil
    }

    func uninstallHooks(_ source: AgentSource) -> String? {
        if let error = HookInstaller.uninstall(source) { return error }
        settings.hooksInstalledByUser.removeAll { $0 == source.rawValue }
        return nil
    }

    func readFile(_ path: String) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int, size < 1_000_000 else { return nil }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }


    // MARK: - Timers

    private func housekeeping() {
        let now = Date()
        for id in pending.expire(now: now) {
            for session in sessions where session.pending.contains(where: { $0.requestID == id }) {
                SessionReducer.markReleased(&sessionState, key: session.key, requestID: id)
            }
            Log.info("session", "request expired", ["request": id])
        }
        if Int(now.timeIntervalSince1970) % 60 == 0 {
            apply(SessionReducer.pruneIdle(&sessionState, now: now, maxIdle: idleCleanup))
        }
        syncPendingCount()
        stateDidChange()
    }

    private func stateDidChange() {
        scheduleTick()
        onStateChanged?()
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
