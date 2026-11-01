import Foundation

/// Pure reducer: hook events in, session state changes and UI/sound effects out.
public enum SessionReducer {
    public static func reduce(_ state: inout SessionState, event: HookEvent, requestID: String?, now: Date) -> [SessionEffect] {
        reduce(&state, event: AgentEventAdapter.normalize(event), requestID: requestID, now: now)
    }

    public static func reduce(_ state: inout SessionState, event normalized: AgentEvent,
                              requestID: String?, now: Date) -> [SessionEffect] {
        let event = normalized.hook
        let key = SessionKey(source: event.source, sessionID: event.sessionID)
        if state.dismissedKeys.contains(key) {
            if normalized.kind == .sessionEnded { state.dismissedKeys.remove(key) }
            return []
        }
        var session = state.sessions[key] ?? Session(key: key, startedAt: now)
        session.lastEventAt = now
        session.missedProcessPolls = 0
        // A session the watcher found first becomes live the moment its hooks fire.
        session.ingress = .hook
        applyIdentity(&session, from: event)
        switch normalized.kind {
        case .permissionRequested, .notification, .heartbeat, .unknown(_):
            break
        default:
            session.hasLifecycleActivity = true
        }
        let statusBefore = session.status
        var effects: [SessionEffect] = []

        switch normalized.kind {
        case .sessionStarted:
            session.status = .idle
        case .promptSubmitted:
            session.status = .working
            if let prompt = event.prompt { session.lastPrompt = prompt }
            effects.append(.sound(.started))
        case .toolStarted:
            session.status = .runningTool(event.toolName ?? "tool")
            session.currentTool = event.toolName
            session.elapsedToolStart = now
        case .toolFinished, .toolFailed:
            session.currentTool = nil
            session.elapsedToolStart = nil
            if let toolUseID = event.toolUseID {
                for req in session.pending where req.event.toolUseID == toolUseID {
                    effects.append(.requestCleared(key, requestID: req.requestID))
                }
                session.pending.removeAll { $0.event.toolUseID == toolUseID }
            }
            session.status = session.pending.last?.status ?? .working
            effects.append(.sound(.actionCompleted))
        case .permissionRequested:
            if let requestID {
                let request = PendingRequest(requestID: requestID, event: event, receivedAt: now)
                session.pending.append(request)
                session.status = request.status
                effects.append(.requestArrived(key, request))
                effects.append(.sound(.inputNeeded))
            } else if session.pending.isEmpty {
                session.status = .waitingForApproval
            }
        case .notification:
            if event.notificationType == "permission_prompt", session.pending.isEmpty {
                session.status = .waitingForApproval
            }
        case .compactingStarted:
            session.status = .compacting
        case .compactingFinished:
            session.status = .working
        case .turnCompleted:
            session.status = .done
            session.currentTool = nil
            if let message = event.lastAssistantMessage { session.lastAssistantMessage = message }
            effects.append(.revealCompletion(key))
            effects.append(.sound(.done))
        case .turnFailed:
            session.status = .failed
            session.currentTool = nil
            effects.append(.revealFailure(key))
            effects.append(.sound(.failed))
        case .subagentStarted:
            let id = subagentID(event)
            let description = (event.raw["agent_type"] as? String) ?? (event.raw["description"] as? String) ?? "subagent"
            if let index = session.subagents.firstIndex(where: { $0.id == id }) {
                session.subagents[index].status = .working
            } else {
                session.subagents.append(Subagent(id: id, description: description, status: .working, startedAt: now))
            }
        case .subagentFinished:
            let id = subagentID(event)
            if let index = session.subagents.firstIndex(where: { $0.id == id }) {
                session.subagents[index].status = .done
            }
        case .sessionEnded:
            state.sessions[key] = nil
            return [.removed(key)]
        case .interrupted:
            // An interrupted turn settles without masquerading as a successful completion card.
            session.status = .idle
            session.currentTool = nil
            session.elapsedToolStart = nil
        case .heartbeat, .unknown:
            break
        }

        if session.status != statusBefore {
            session.statusChangedAt = now
            if session.status.animationFamily != statusBefore.animationFamily { session.animationPhaseStart = now }
        }
        state.sessions[key] = session
        return effects
    }

    /// The user answered (or the app released) the request; the card goes away.
    public static func clearRequest(_ state: inout SessionState, key: SessionKey, requestID: String) -> [SessionEffect] {
        guard var session = state.sessions[key], session.pending.contains(where: { $0.requestID == requestID }) else { return [] }
        session.pending.removeAll { $0.requestID == requestID }
        if session.pending.isEmpty, !session.hasLifecycleActivity {
            state.sessions[key] = nil
            return [.requestCleared(key, requestID: requestID), .removed(key)]
        }
        session.status = session.pending.last?.status ?? .working
        state.sessions[key] = session
        return [.requestCleared(key, requestID: requestID)]
    }

    /// Removes a card and suppresses rediscovery until the agent emits SessionEnd or Reef restarts.
    public static func dismiss(_ state: inout SessionState, key: SessionKey) -> [SessionEffect] {
        guard state.sessions.removeValue(forKey: key) != nil else { return [] }
        state.dismissedKeys.insert(key)
        return [.removed(key)]
    }

    /// The request was handed back to the terminal; keep showing it read-only.
    public static func markReleased(_ state: inout SessionState, key: SessionKey, requestID: String) {
        guard var session = state.sessions[key],
              let index = session.pending.firstIndex(where: { $0.requestID == requestID }) else { return }
        session.pending[index].isLive = false
        state.sessions[key] = session
    }

    /// How long a transcript may claim an unfinished turn before Reef stops believing it. A
    /// crashed editor writes no closing record, and a card stuck on "working" also suppresses
    /// the all-finished notification for every real session.
    public static let staleWorkAfter: TimeInterval = 30 * 60

    /// Creates or updates a session read from a transcript. Hooks win: when a session with this
    /// key already arrived through hooks the transcript is ignored entirely, because the hook
    /// path carries approvals and the transcript cannot.
    @discardableResult
    public static func upsertWatched(_ state: inout SessionState, _ transcript: TranscriptSession,
                                     key: SessionKey, now: Date) -> [SessionEffect] {
        guard !state.dismissedKeys.contains(key) else { return [] }
        if let existing = state.sessions[key], existing.ingress == .hook { return [] }

        let existed = state.sessions[key] != nil
        var session = state.sessions[key] ?? Session(key: key, startedAt: transcript.startedAt)
        let previousStatus = session.status
        let wasDone = previousStatus == .done
        session.ingress = .transcript
        session.lastEventAt = transcript.lastActivityAt
        session.cwd = transcript.cwd
        if let cwd = transcript.cwd { session.project = URL(fileURLWithPath: cwd).lastPathComponent }
        session.model = transcript.model
        session.lastAssistantMessage = transcript.lastAssistantMessage
        // A watched session is reachable in its editor, so the jump engine opens VS Code there.
        session.terminal = TerminalIdentity(bundleID: JumpPlanner.vscodeBundle)
        // A transcript whose first records carry no turn yet is a session just opening, not one
        // that finished: calling it done would flash a completion the moment it starts.
        let hasFinishedATurn = transcript.turnCount > 0 || transcript.lastAssistantMessage != nil
        let working = transcript.isWorking && now.timeIntervalSince(transcript.lastActivityAt) < staleWorkAfter
        let status: SessionStatus = working ? .working : (transcript.isWorking ? .idle : (hasFinishedATurn ? .done : .idle))
        if session.status != status {
            session.statusChangedAt = now
            if session.status.animationFamily != status.animationFamily { session.animationPhaseStart = now }
            session.status = status
        }
        state.sessions[key] = session

        // Only transitions that happen while Reef is watching are worth sounding. A session
        // already working or done when first discovered joins silently.
        guard existed else { return [] }
        if status.animationFamily == .working, previousStatus.animationFamily != .working {
            return [.sound(.started)]
        }
        guard status == .done, !wasDone else { return [] }
        return [.revealCompletion(key), .sound(.done)]
    }

    /// Drops every transcript-sourced session, for when the user turns watching off.
    @discardableResult
    public static func removeWatched(_ state: inout SessionState) -> [SessionEffect] {
        var effects: [SessionEffect] = []
        for (key, session) in state.sessions where session.ingress == .transcript {
            state.sessions[key] = nil
            effects.append(.removed(key))
        }
        return effects
    }

    public static func pruneIdle(_ state: inout SessionState, now: Date, maxIdle: TimeInterval) -> [SessionEffect] {
        var effects: [SessionEffect] = []
        for (key, session) in state.sessions where now.timeIntervalSince(session.lastEventAt) > maxIdle && session.pending.isEmpty {
            state.sessions[key] = nil
            effects.append(.removed(key))
        }
        return effects
    }

    /// Reconciles coarse process discovery with hook sessions. Two misses plus a quiet grace
    /// period are required so short-lived Codex subprocesses and transient `ps` failures do not
    /// make cards flicker.
    public static func reconcileProcessLiveness(_ state: inout SessionState,
                                                aliveProcessIDs: Set<Int>,
                                                aliveSources: Set<AgentSource>,
                                                now: Date,
                                                quietGrace: TimeInterval = 90) -> [SessionEffect] {
        var effects: [SessionEffect] = []
        for (key, var session) in state.sessions where session.ingress == .hook {
            // The bridge process itself is short-lived; its parent is the agent that invoked the
            // hook. When that identity is available it is authoritative. Falling back to source
            // presence is only for old/headless events that carried no usable process identity.
            let ownerPID = session.terminal.ppid
            let alive = ownerPID.map(aliveProcessIDs.contains) ?? aliveSources.contains(key.source)
            if alive {
                session.missedProcessPolls = 0
                session.processObservedAt = now
                state.sessions[key] = session
                continue
            }
            session.missedProcessPolls += 1
            let quiet = now.timeIntervalSince(session.lastEventAt) >= quietGrace
            if session.missedProcessPolls >= 2, quiet, session.pending.isEmpty {
                state.sessions[key] = nil
                effects.append(.removed(key))
            } else {
                state.sessions[key] = session
            }
        }
        return effects
    }

    // MARK: - Helpers

    private static func applyIdentity(_ session: inout Session, from event: HookEvent) {
        if let cwd = event.cwd { session.cwd = cwd }
        if let model = event.model { session.model = model }
        let reef = event.raw["reef"] as? [String: Any]
        let git = reef?["git"] as? [String: Any]
        if let root = git?["root"] as? String {
            session.project = URL(fileURLWithPath: root).lastPathComponent
        } else if session.project == nil, let cwd = event.cwd {
            session.project = URL(fileURLWithPath: cwd).lastPathComponent
        }
        if let branch = git?["branch"] as? String { session.branch = branch }
        if reef != nil {
            let identity = TerminalIdentity.from(raw: event.raw)
            if !identity.isHeadless || session.terminal.isHeadless { session.terminal = identity }
        }
    }

    private static func subagentID(_ event: HookEvent) -> String {
        (event.raw["agent_id"] as? String) ?? event.toolUseID ?? UUID().uuidString
    }
}
