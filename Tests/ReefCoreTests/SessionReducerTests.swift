import XCTest
@testable import ReefCore

final class SessionReducerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func event(_ name: String, source: AgentSource = .claude, session: String = "s1", extra: [String: Any] = [:]) -> HookEvent {
        var json: [String: Any] = ["hook_event_name": name, "session_id": session, "cwd": "/tmp/myproj"]
        for (k, v) in extra { json[k] = v }
        return try! HookEvent(source: source, json: json)
    }

    private func apply(_ state: inout SessionState, _ e: HookEvent, requestID: String? = nil, at: TimeInterval = 0) -> [SessionEffect] {
        SessionReducer.reduce(&state, event: e, requestID: requestID, now: t0.addingTimeInterval(at))
    }

    var key: SessionKey { SessionKey(source: .claude, sessionID: "s1") }

    func testLifecycleIdleWorkingToolDone() {
        var s = SessionState()
        _ = apply(&s, event("SessionStart"))
        XCTAssertEqual(s.sessions[key]?.status, .idle)
        XCTAssertEqual(s.sessions[key]?.project, "myproj")
        _ = apply(&s, event("UserPromptSubmit", extra: ["prompt": "fix the bug"]))
        XCTAssertEqual(s.sessions[key]?.status, .working)
        XCTAssertEqual(s.sessions[key]?.lastPrompt, "fix the bug")
        _ = apply(&s, event("PreToolUse", extra: ["tool_name": "Bash", "tool_use_id": "t1"]))
        XCTAssertEqual(s.sessions[key]?.status, .runningTool("Bash"))
        XCTAssertEqual(s.sessions[key]?.currentTool, "Bash")
        _ = apply(&s, event("PostToolUse", extra: ["tool_name": "Bash", "tool_use_id": "t1"]))
        XCTAssertEqual(s.sessions[key]?.status, .working)
        XCTAssertNil(s.sessions[key]?.currentTool)
        let effects = apply(&s, event("Stop", extra: ["last_assistant_message": "All fixed."]))
        XCTAssertEqual(s.sessions[key]?.status, .done)
        XCTAssertEqual(s.sessions[key]?.lastAssistantMessage, "All fixed.")
        XCTAssertEqual(effects, [.revealCompletion(key), .sound(.done)])
    }

    func testWorkStartAndActionCompletionHaveDistinctSounds() {
        var state = SessionState()
        _ = apply(&state, event("SessionStart"))
        XCTAssertEqual(apply(&state, event("UserPromptSubmit")), [.sound(.started)])
        _ = apply(&state, event("PreToolUse", extra: ["tool_name": "Bash", "tool_use_id": "t1"]))
        XCTAssertEqual(apply(&state, event("PostToolUse", extra: ["tool_name": "Bash", "tool_use_id": "t1"])),
                       [.sound(.actionCompleted)])
    }

    func testPermissionRequestAddsPendingAndSound() {
        var s = SessionState()
        _ = apply(&s, event("SessionStart"))
        let e = event("PermissionRequest", extra: ["tool_name": "Bash", "tool_use_id": "t9", "tool_input": ["command": "rm x"]])
        let effects = apply(&s, e, requestID: "r1", at: 5)
        XCTAssertEqual(s.sessions[key]?.status, .waitingForApproval)
        XCTAssertEqual(s.sessions[key]?.pending.count, 1)
        XCTAssertEqual(s.sessions[key]?.pending.first?.requestID, "r1")
        XCTAssertEqual(s.sessions[key]?.pending.first?.kind, .permission)
        XCTAssertTrue(s.sessions[key]?.pending.first?.isLive ?? false)
        XCTAssertEqual(effects.count, 2)
        XCTAssertEqual(effects.last, .sound(.inputNeeded))
        if case let .requestArrived(k, req) = effects[0] { XCTAssertEqual(k, key); XCTAssertEqual(req.requestID, "r1") } else { XCTFail("expected requestArrived") }
    }

    func testPostToolUseClearsPendingByToolUseID() {
        var s = SessionState()
        _ = apply(&s, event("PermissionRequest", extra: ["tool_name": "Bash", "tool_use_id": "t9"]), requestID: "r1")
        let effects = apply(&s, event("PostToolUse", extra: ["tool_name": "Bash", "tool_use_id": "t9"]))
        XCTAssertEqual(s.sessions[key]?.pending.count, 0)
        XCTAssertEqual(s.sessions[key]?.status, .working)
        XCTAssertTrue(effects.contains(.requestCleared(key, requestID: "r1")))
    }

    func testSameSessionIDDifferentSourcesAreDistinct() {
        var s = SessionState()
        _ = apply(&s, event("SessionStart", source: .claude))
        _ = apply(&s, event("SessionStart", source: .codex))
        XCTAssertEqual(s.sessions.count, 2)
    }

    func testSessionEndRemoves() {
        var s = SessionState()
        _ = apply(&s, event("SessionStart"))
        let effects = apply(&s, event("SessionEnd"))
        XCTAssertTrue(s.sessions.isEmpty)
        XCTAssertEqual(effects, [.removed(key)])
    }

    func testPruneIdleRemovesAfterTwoHoursOnly() {
        var s = SessionState()
        _ = apply(&s, event("SessionStart"))
        let twoHours: TimeInterval = 2 * 3600
        XCTAssertEqual(SessionReducer.pruneIdle(&s, now: t0.addingTimeInterval(twoHours - 60), maxIdle: twoHours), [])
        XCTAssertEqual(s.sessions.count, 1)
        XCTAssertEqual(SessionReducer.pruneIdle(&s, now: t0.addingTimeInterval(twoHours + 60), maxIdle: twoHours), [.removed(key)])
        XCTAssertTrue(s.sessions.isEmpty)
    }

    func testUnknownSessionEventCreatesSession() {
        var s = SessionState()
        _ = apply(&s, event("Stop"))
        XCTAssertEqual(s.sessions[key]?.status, .done)
    }

    func testProjectNameFromGitRootOverCwd() {
        var s = SessionState()
        _ = apply(&s, event("SessionStart", extra: ["reef": ["git": ["root": "/Users/x/Code/repo-name", "branch": "feat/x"]]]))
        XCTAssertEqual(s.sessions[key]?.project, "repo-name")
        XCTAssertEqual(s.sessions[key]?.branch, "feat/x")
    }

    func testQuestionAndPlanKindsDetected() {
        var s = SessionState()
        _ = apply(&s, event("PermissionRequest", extra: ["tool_name": "AskUserQuestion", "tool_use_id": "q1"]), requestID: "r1")
        XCTAssertEqual(s.sessions[key]?.pending.first?.kind, .question)
        XCTAssertEqual(s.sessions[key]?.status, .waitingForQuestion)
        _ = apply(&s, event("PermissionRequest", extra: ["tool_name": "ExitPlanMode", "tool_use_id": "p1"]), requestID: "r2")
        XCTAssertEqual(s.sessions[key]?.pending.last?.kind, .plan)
        XCTAssertEqual(s.sessions[key]?.status, .waitingForPlan)
    }

    func testClearRequestRestoresWorkingAndCollapsesStatus() {
        var s = SessionState()
        _ = apply(&s, event("SessionStart"))
        _ = apply(&s, event("PermissionRequest", extra: ["tool_name": "Bash", "tool_use_id": "t1"]), requestID: "r1")
        let effects = SessionReducer.clearRequest(&s, key: key, requestID: "r1")
        XCTAssertEqual(effects, [.requestCleared(key, requestID: "r1")])
        XCTAssertEqual(s.sessions[key]?.status, .working)
    }

    func testStandaloneRequestIsRemovedAfterItIsAnswered() {
        var s = SessionState()
        _ = apply(&s, event("PermissionRequest", extra: ["tool_name": "AskUserQuestion"]), requestID: "r1")
        XCTAssertEqual(SessionReducer.clearRequest(&s, key: key, requestID: "r1"),
                       [.requestCleared(key, requestID: "r1"), .removed(key)])
        XCTAssertNil(s.sessions[key])
    }

    func testReleasedRequestStaysVisibleReadOnly() {
        var s = SessionState()
        _ = apply(&s, event("PermissionRequest", extra: ["tool_name": "Bash", "tool_use_id": "t1"]), requestID: "r1")
        SessionReducer.markReleased(&s, key: key, requestID: "r1")
        XCTAssertEqual(s.sessions[key]?.pending.count, 1)
        XCTAssertFalse(s.sessions[key]?.pending.first?.isLive ?? true)
    }

    func testNotificationPermissionPromptWithoutRequestIsWaitingReadOnly() {
        var s = SessionState()
        _ = apply(&s, event("SessionStart"))
        _ = apply(&s, event("Notification", extra: ["notification_type": "permission_prompt"]))
        XCTAssertEqual(s.sessions[key]?.status, .waitingForApproval)
        XCTAssertEqual(s.sessions[key]?.pending.count, 0)
    }

    func testSubagentsTracked() {
        var s = SessionState()
        _ = apply(&s, event("SubagentStart", extra: ["agent_id": "a1", "agent_type": "Explore"]))
        XCTAssertEqual(s.sessions[key]?.subagents.count, 1)
        XCTAssertEqual(s.sessions[key]?.subagents.first?.status, .working)
        _ = apply(&s, event("SubagentStop", extra: ["agent_id": "a1"]))
        XCTAssertEqual(s.sessions[key]?.subagents.first?.status, .done)
    }

    func testStopFailureRevealsFailure() {
        var s = SessionState()
        let effects = apply(&s, event("StopFailure"))
        XCTAssertEqual(s.sessions[key]?.status, .failed)
        XCTAssertEqual(effects, [.revealFailure(key), .sound(.failed)])
    }

    func testTerminalIdentityFromRaw() {
        let raw: [String: Any] = ["reef": ["tty": "/dev/ttys003", "pid": 42, "ppid": 41, "title_marker": "reef:abcdefgh",
                                           "env": ["KITTY_WINDOW_ID": "7", "KITTY_PID": "99", "TMUX_PANE": "%3",
                                                   "__CFBundleIdentifier": "net.kovidgoyal.kitty", "TERM_PROGRAM": "kitty"]]]
        let t = TerminalIdentity.from(raw: raw)
        XCTAssertEqual(t.tty, "/dev/ttys003"); XCTAssertEqual(t.kittyWindowID, 7); XCTAssertEqual(t.kittyPID, 99)
        XCTAssertEqual(t.tmuxPane, "%3"); XCTAssertEqual(t.bundleID, "net.kovidgoyal.kitty"); XCTAssertEqual(t.termProgram, "kitty")
        XCTAssertEqual(t.ghosttyMarker, "reef:abcdefgh"); XCTAssertFalse(t.isHeadless)
        XCTAssertTrue(TerminalIdentity.from(raw: [:]).isHeadless)
    }

    // MARK: - Stage 2: animation phase origin, seed and model

    func testStatusChangedAtOnlyMovesWhenStatusChanges() {
        var s = SessionState()
        _ = apply(&s, event("SessionStart"), at: 0)
        let created = s.sessions[key]?.statusChangedAt
        _ = apply(&s, event("UserPromptSubmit"), at: 10)
        let working = s.sessions[key]?.statusChangedAt
        XCTAssertEqual(working, t0.addingTimeInterval(10))
        XCTAssertNotEqual(created, working)
        _ = apply(&s, event("Notification"), at: 20)
        XCTAssertEqual(s.sessions[key]?.statusChangedAt, working, "same status keeps the phase origin")
    }

    func testRapidToolFlipsKeepAdvancingThePhase() {
        var s = SessionState()
        for i in 0..<6 {
            _ = apply(&s, event("PreToolUse", extra: ["tool_name": "Bash", "tool_use_id": "t\(i)"]), at: Double(i) * 0.1)
            _ = apply(&s, event("PostToolUse", extra: ["tool_name": "Bash", "tool_use_id": "t\(i)"]), at: Double(i) * 0.1 + 0.05)
        }
        XCTAssertEqual(s.sessions[key]?.statusChangedAt, t0.addingTimeInterval(0.55))
        XCTAssertEqual(s.sessions[key]?.status, .working)
    }

    func testModelIsRecorded() {
        var s = SessionState()
        _ = apply(&s, event("UserPromptSubmit", extra: ["model": "claude-opus-5"]))
        XCTAssertEqual(s.sessions[key]?.model, "claude-opus-5")
        _ = apply(&s, event("PostToolUse"))
        XCTAssertEqual(s.sessions[key]?.model, "claude-opus-5", "an event without a model keeps the known one")
    }

    // MARK: - Watched (transcript) sessions

    private func codexEvent(_ name: String, session: String) -> HookEvent {
        event(name, source: .codex, session: session)
    }

    private func transcript(_ id: String, cwd: String = "/tmp/proj", model: String? = "gpt-5.6-sol",
                            working: Bool = true, message: String? = nil, turns: Int = 1) -> TranscriptSession {
        TranscriptSession(id: id, cwd: cwd, originator: "codex_vscode", model: model, isWorking: working,
                          lastAssistantMessage: message, startedAt: t0, lastActivityAt: t0, turnCount: turns)
    }

    func testWatchedSessionAppearsAndTracksTurns() {
        var s = SessionState()
        var t = transcript("w1")
        let key = SessionKey(source: .codex, sessionID: "w1")
        _ = SessionReducer.upsertWatched(&s, t, key: key, now: t0)
        XCTAssertEqual(s.sessions[key]?.status, .working)
        XCTAssertEqual(s.sessions[key]?.ingress, .transcript)
        XCTAssertEqual(s.sessions[key]?.project, "proj")
        XCTAssertEqual(s.sessions[key]?.model, "gpt-5.6-sol")
        XCTAssertEqual(s.sessions[key]?.terminal.bundleID, JumpPlanner.vscodeBundle, "clicking it focuses VS Code")
        t.isWorking = false
        t.lastAssistantMessage = "Done."
        let effects = SessionReducer.upsertWatched(&s, t, key: key, now: t0.addingTimeInterval(5))
        XCTAssertEqual(s.sessions[key]?.status, .done)
        XCTAssertEqual(s.sessions[key]?.lastAssistantMessage, "Done.")
        XCTAssertTrue(effects.contains(.revealCompletion(key)))
        let again = SessionReducer.upsertWatched(&s, t, key: key, now: t0.addingTimeInterval(6))
        XCTAssertFalse(again.contains(.revealCompletion(key)), "a finished session reveals once, not on every poll")
    }

    func testHookSessionIsNeverOverwrittenByATranscript() {
        var s = SessionState()
        let key = SessionKey(source: .codex, sessionID: "dup")
        _ = apply(&s, codexEvent("UserPromptSubmit", session: "dup"))
        let before = s.sessions[key]
        let t = transcript("dup", cwd: "/tmp/other", model: nil, working: false, message: "x", turns: 9)
        XCTAssertEqual(SessionReducer.upsertWatched(&s, t, key: key, now: t0), [])
        XCTAssertEqual(s.sessions[key], before, "hooks win; they carry approvals")
        XCTAssertEqual(s.sessions.count, 1)
    }

    func testAFinishedSessionSeenForTheFirstTimeIsSilent() {
        var s = SessionState()
        let key = SessionKey(source: .codex, sessionID: "old")
        let t = transcript("old", working: false, message: "All done.", turns: 3)
        let effects = SessionReducer.upsertWatched(&s, t, key: key, now: t0)
        XCTAssertEqual(s.sessions[key]?.status, .done)
        XCTAssertEqual(effects, [], "a session that ended before Reef started must not open the panel")
    }

    func testASessionWithNoTurnsYetIsIdleNotDone() {
        var s = SessionState()
        let key = SessionKey(source: .codex, sessionID: "fresh")
        let t = transcript("fresh", working: false, message: nil, turns: 0)
        _ = SessionReducer.upsertWatched(&s, t, key: key, now: t0)
        XCTAssertEqual(s.sessions[key]?.status, .idle, "the first record of a new session is not a finished turn")
    }

    func testAWatchedTurnThatWentQuietStopsClaimingToWork() {
        // A crashed or killed editor leaves a transcript whose last record says a turn began.
        // Reporting that as working for hours also gags the "all agents finished" notification.
        var s = SessionState()
        let key = SessionKey(source: .codex, sessionID: "stale")
        var t = transcript("stale", working: true)
        t.lastActivityAt = t0.addingTimeInterval(-SessionReducer.staleWorkAfter - 60)
        let effects = SessionReducer.upsertWatched(&s, t, key: key, now: t0)
        XCTAssertEqual(s.sessions[key]?.status, .idle)
        XCTAssertEqual(effects, [], "a turn nobody is running is not a completion")
    }

    func testAHookEventTakesOverAWatchedSession() {
        var s = SessionState()
        let key = SessionKey(source: .codex, sessionID: "takeover")
        _ = SessionReducer.upsertWatched(&s, transcript("takeover"), key: key, now: t0)
        XCTAssertEqual(s.sessions[key]?.ingress, .transcript)
        _ = apply(&s, codexEvent("UserPromptSubmit", session: "takeover"))
        XCTAssertEqual(s.sessions[key]?.ingress, .hook, "once hooks fire the session is live, not read-only")
        XCTAssertEqual(s.sessions.count, 1)
    }

    func testRemoveWatchedLeavesHookSessions() {
        var s = SessionState()
        _ = apply(&s, codexEvent("SessionStart", session: "hooked"))
        _ = SessionReducer.upsertWatched(&s, transcript("w"), key: SessionKey(source: .codex, sessionID: "w"), now: t0)
        XCTAssertEqual(s.sessions.count, 2)
        let effects = SessionReducer.removeWatched(&s)
        XCTAssertEqual(s.sessions.count, 1)
        XCTAssertEqual(effects.count, 1)
        XCTAssertEqual(s.sessions.values.first?.ingress, .hook)
    }

    func testWatchedSessionsNeverCarryPendingRequests() {
        var s = SessionState()
        let key = SessionKey(source: .codex, sessionID: "w2")
        _ = SessionReducer.upsertWatched(&s, transcript("w2"), key: key, now: t0)
        XCTAssertTrue(s.sessions[key]?.pending.isEmpty ?? false, "a transcript cannot answer an approval")
    }

    func testAnimationSeedIsStableAndDiffersPerSession() {
        var s = SessionState()
        _ = apply(&s, event("SessionStart", session: "a"))
        _ = apply(&s, event("SessionStart", session: "b"))
        let keyA = SessionKey(source: .claude, sessionID: "a")
        let a1 = s.sessions[keyA]?.animationSeed
        XCTAssertNotNil(a1)
        _ = apply(&s, event("UserPromptSubmit", session: "a"))
        XCTAssertEqual(s.sessions[keyA]?.animationSeed, a1)
        XCTAssertNotEqual(a1, s.sessions[SessionKey(source: .claude, sessionID: "b")]?.animationSeed)
    }

    func testAgentEventAdapterNormalizesAlternateSpellings() {
        XCTAssertEqual(AgentEventAdapter.normalize(event("tool_execution_start")).kind, .toolStarted)
        XCTAssertEqual(AgentEventAdapter.normalize(event("agent_settled")).kind, .turnCompleted)
        XCTAssertEqual(AgentEventAdapter.normalize(event("StopCancelled")).kind, .interrupted)
    }

    func testInterruptedTurnDoesNotRevealACompletion() {
        var s = SessionState()
        _ = apply(&s, event("UserPromptSubmit"))
        let effects = apply(&s, event("Interrupt"))
        XCTAssertEqual(s.sessions[key]?.status, .idle)
        XCTAssertFalse(effects.contains(.revealCompletion(key)))
    }

    func testProcessLivenessRequiresTwoQuietMisses() {
        var s = SessionState()
        _ = apply(&s, event("SessionStart"), at: 0)
        let late = t0.addingTimeInterval(200)
        XCTAssertEqual(SessionReducer.reconcileProcessLiveness(&s, aliveProcessIDs: [], aliveSources: [], now: late), [])
        XCTAssertEqual(s.sessions[key]?.missedProcessPolls, 1)
        XCTAssertEqual(SessionReducer.reconcileProcessLiveness(&s, aliveProcessIDs: [], aliveSources: [], now: late.addingTimeInterval(2)),
                       [.removed(key)])
        XCTAssertNil(s.sessions[key])
    }

    func testProcessObservationResetsMissCounter() {
        var s = SessionState()
        _ = apply(&s, event("SessionStart"), at: 0)
        _ = SessionReducer.reconcileProcessLiveness(&s, aliveProcessIDs: [], aliveSources: [], now: t0.addingTimeInterval(200))
        _ = SessionReducer.reconcileProcessLiveness(&s, aliveProcessIDs: [], aliveSources: [.claude], now: t0.addingTimeInterval(201))
        XCTAssertEqual(s.sessions[key]?.missedProcessPolls, 0)
        XCTAssertEqual(s.sessions[key]?.processObservedAt, t0.addingTimeInterval(201))
    }


    func testPerSessionParentProcessBeatsCoarseSourcePresence() {
        var s = SessionState()
        let identified = event("SessionStart", extra: ["reef": ["pid": 101, "ppid": 42, "env": [:]]])
        _ = apply(&s, identified, at: 0)
        let late = t0.addingTimeInterval(200)
        _ = SessionReducer.reconcileProcessLiveness(&s, aliveProcessIDs: [], aliveSources: [.claude], now: late)
        XCTAssertEqual(s.sessions[key]?.missedProcessPolls, 1,
                       "another Claude process must not keep this dead session alive")
        _ = SessionReducer.reconcileProcessLiveness(&s, aliveProcessIDs: [42], aliveSources: [], now: late.addingTimeInterval(1))
        XCTAssertEqual(s.sessions[key]?.missedProcessPolls, 0)
    }
}
