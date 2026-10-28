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
        _ = apply(&s, event("PermissionRequest", extra: ["tool_name": "Bash", "tool_use_id": "t1"]), requestID: "r1")
        let effects = SessionReducer.clearRequest(&s, key: key, requestID: "r1")
        XCTAssertEqual(effects, [.requestCleared(key, requestID: "r1")])
        XCTAssertEqual(s.sessions[key]?.status, .working)
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
}
