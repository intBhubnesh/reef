import XCTest
@testable import ReefCore

/// Regression tests for the Stage 2 final-review findings.
final class ReviewFixStage2Tests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 2_000_000)

    private func event(_ name: String, extra: [String: Any] = [:]) -> HookEvent {
        var json: [String: Any] = ["hook_event_name": name, "session_id": "s1", "cwd": "/tmp/p"]
        for (k, v) in extra { json[k] = v }
        return try! HookEvent(source: .claude, json: json)
    }

    private func apply(_ s: inout SessionState, _ e: HookEvent, at: TimeInterval) {
        _ = SessionReducer.reduce(&s, event: e, requestID: nil, now: t0.addingTimeInterval(at))
    }

    private var key: SessionKey { SessionKey(source: .claude, sessionID: "s1") }

    // Critical 2: a busy agent must keep animating. Tool calls change `status` several times a
    // second; if the animation phase restarted with them the character would freeze on frame 0.
    func testAnimationPhaseSurvivesToolChurn() {
        var s = SessionState()
        apply(&s, event("UserPromptSubmit"), at: 0)
        let origin = s.sessions[key]?.animationPhaseStart
        XCTAssertEqual(origin, t0)
        for i in 0..<6 {
            apply(&s, event("PreToolUse", extra: ["tool_name": "Bash", "tool_use_id": "t\(i)"]), at: Double(i) * 0.2)
            apply(&s, event("PostToolUse", extra: ["tool_name": "Bash", "tool_use_id": "t\(i)"]), at: Double(i) * 0.2 + 0.1)
        }
        XCTAssertEqual(s.sessions[key]?.animationPhaseStart, origin,
                       "running tools stays in the working family, so the cycle must keep running")
        XCTAssertEqual(s.sessions[key]?.status, .working)
    }

    func testAnimationPhaseRestartsWhenTheFamilyChanges() {
        var s = SessionState()
        apply(&s, event("UserPromptSubmit"), at: 0)
        apply(&s, event("Stop", extra: ["last_assistant_message": "done"]), at: 10)
        XCTAssertEqual(s.sessions[key]?.animationPhaseStart, t0.addingTimeInterval(10),
                       "finishing is a new family, so the blink starts now")
    }

    func testAnimationFamilyGrouping() {
        XCTAssertEqual(SessionStatus.idle.animationFamily, .working)
        XCTAssertEqual(SessionStatus.runningTool("Bash").animationFamily, .working)
        XCTAssertEqual(SessionStatus.compacting.animationFamily, .working)
        XCTAssertEqual(SessionStatus.waitingForQuestion.animationFamily, .waiting)
        XCTAssertEqual(SessionStatus.done.animationFamily, .done)
        XCTAssertEqual(SessionStatus.failed.animationFamily, .failed)
    }

    // Important 9: an agent can wait for hours. The eye schedule must cost the same at any age.
    func testWaitingEyeScheduleCostIsBounded() {
        let started = Date()
        _ = SpriteAnimator.frame(status: .waitingForApproval, elapsed: 8 * 3600, seed: 3)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.05,
                          "an 8-hour-old waiting state must not replay its whole schedule")
    }

    func testWaitingEyesStillMoveAfterHours() {
        let late = (0..<40).map { SpriteAnimator.frame(status: .waitingForApproval,
                                                       elapsed: 8 * 3600 + Double($0) * 0.05, seed: 3).eyesOpen }
        XCTAssertTrue(late.contains(true) && late.contains(false))
    }

    // Critical 1: Reef owns the status line, so whatever it prints is the user's status line.
    // Printing the raw payload back would dump session JSON under every prompt.
    func testStatusLineCacheWritesTheCacheAndPrintsNothing() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("reef-sl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cache = dir.appendingPathComponent("rl.json").path
        let payload = #"{"session_id":"abc","cwd":"/secret/path","rate_limits":{"five_hour":{"used_percentage":12}}}"#
        var out = Data()
        let code = BridgeCLI.run(arguments: ["--task", "statusline-cache", "--cache-file", cache],
                                 stdin: payload.data(using: .utf8)!,
                                 env: ["HOME": dir.path]) { out.append($0) }
        XCTAssertEqual(code, 0)
        XCTAssertTrue(out.isEmpty, "the status line must stay empty, not echo the payload")
        let snapshot = UsageSnapshot.parse(try Data(contentsOf: URL(fileURLWithPath: cache)), now: Date())
        XCTAssertEqual(snapshot?.fiveHour?.usedPercent, 12)
    }

    func testStatusLineCacheSurvivesJunkInput() {
        var out = Data()
        for junk in ["not json", "", "[]", "{}"] {
            out = Data()
            let code = BridgeCLI.run(arguments: ["--task", "statusline-cache"], stdin: junk.data(using: .utf8)!,
                                     env: ["HOME": NSTemporaryDirectory()]) { out.append($0) }
            XCTAssertEqual(code, 0, junk)
            XCTAssertTrue(out.isEmpty, junk)
        }
    }

    // Important 4: the dwell belongs to the state machine; the view must not add it again.
    func testHoverDwellIsNotAppliedTwice() {
        XCTAssertEqual(NotchTransition.hoverExpand.delay, 0,
                       "NotchMachine already waited the dwell before the state changed")
        XCTAssertEqual(NotchTransition.requestExpand.delay, Motion.requestExpandDelay)
    }
}
