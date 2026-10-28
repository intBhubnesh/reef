import AppKit
import Observation
import ReefCore

/// Owns every piece of live state: sessions, the notch machine, pending requests and the socket server.
@MainActor @Observable
final class AppState {
    var sessionState = SessionState()
    var notch = NotchMachine(timing: NotchTiming())
    var muted = false
    var showHeadless = false
    var idleCleanup: TimeInterval = 2 * 3600
    var revealedKeys: Set<SessionKey> = []

    @ObservationIgnored let pending = PendingRequests()
    @ObservationIgnored private let server: UnixSocketServer
    @ObservationIgnored private let serverQueue = DispatchQueue(label: "app.reef.socket")
    @ObservationIgnored private var deadlineTimer: Timer?
    @ObservationIgnored private var housekeepingTimer: Timer?
    @ObservationIgnored var onStateChanged: (() -> Void)?

    static let waitDeadline: TimeInterval = 3600

    init() {
        server = UnixSocketServer(path: Paths.socketPath, queue: serverQueue)
        server.onRequest = { [weak self] request, connection in
            DispatchQueue.main.async { self?.handle(request: request, connection: connection) }
        }
        pending.onDropped = { [weak self] requestID in self?.requestDropped(requestID) }
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
        apply(effects)
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
                syncPendingCount()
                notch.apply(.requestArrived(now))
            case let .requestCleared(_, requestID):
                pending.release(requestID: requestID)
                syncPendingCount()
                notch.apply(.requestsCleared(now))
            case let .revealCompletion(key):
                revealedKeys.insert(key)
                notch.apply(.taskComplete(now))
            case let .revealFailure(key):
                revealedKeys.insert(key)
                notch.apply(.taskFailed(now))
            case let .sound(kind):
                Log.info("sound", kind.rawValue, ["muted": muted ? "1" : "0"])
            case let .removed(key):
                revealedKeys.remove(key)
                pending.releaseAll(for: key)
                syncPendingCount()
                notch.apply(.requestsCleared(now))
            }
        }
        stateDidChange()
    }

    private func syncPendingCount() {
        notch.pendingCount = livePendingCount
    }

    // MARK: - User intents

    func hover(inside: Bool) {
        let now = Date()
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
        apply(SessionReducer.clearRequest(&sessionState, key: entry.session.key, requestID: requestID))
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
