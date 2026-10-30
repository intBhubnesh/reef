import XCTest
@testable import ReefCore

final class SpriteAnimatorTests: XCTestCase {
    private func f(_ s: SessionStatus, _ t: TimeInterval, seed: UInt64 = 1) -> SpriteFrame {
        SpriteAnimator.frame(status: s, elapsed: t, seed: seed)
    }

    func testWorkingStepsEveryFramePeriodAndWrapsAtEight() {
        XCTAssertEqual(f(.working, 0).bodyFrame, 0)
        XCTAssertEqual(f(.working, 0.149).bodyFrame, 0)
        XCTAssertEqual(f(.working, 0.151).bodyFrame, 1)
        XCTAssertEqual(f(.working, 1.21).bodyFrame, 0, "8-step cycle is 1.2 s")
        XCTAssertNil(f(.working, 0.5).glyph)
        XCTAssertTrue(f(.idle, 0.5).eyesOpen)
    }

    func testWorkingEyesMoveEveryStepSoSomethingChangesAt150ms() {
        // M12: the eyes move every step and the body only every fourth, so a working agent
        // must look different on every 150 ms frame, not every 600 ms.
        let frames = (0..<8).map { f(.working, Double($0) * 0.15 + 0.01) }
        for i in 0..<7 {
            XCTAssertNotEqual(frames[i], frames[i + 1], "step \(i) and \(i + 1) look identical")
        }
        XCTAssertEqual(Set(frames.map(\.eyeShift)).count, 3, "eyes use three positions")
        XCTAssertEqual(f(.working, 0.01).eyeShift, f(.working, 1.21).eyeShift, "the cycle repeats at 1.2 s")
    }

    func testRunningToolAndCompactingUseTheWorkingCycle() {
        XCTAssertEqual(f(.runningTool("Bash"), 0.451).bodyFrame, 3)
        XCTAssertEqual(f(.compacting, 0.451).bodyFrame, 3)
    }

    func testWaitingBobsAtTheMeasuredPeriod() {
        XCTAssertEqual(f(.waitingForApproval, 0).glyph, .question)
        XCTAssertTrue(f(.waitingForApproval, 0.1).glyphRaised)
        XCTAssertFalse(f(.waitingForApproval, 0.4).glyphRaised)
        XCTAssertTrue(f(.waitingForApproval, 0.9).glyphRaised, "period is 0.88 s")
        XCTAssertEqual(f(.waitingForQuestion, 0.1).glyph, .question)
        XCTAssertEqual(f(.waitingForPlan, 0.1).glyph, .question)
    }

    func testTwoSeedsBlinkOutOfPhase() {
        let a = (0..<60).map { f(.waitingForApproval, Double($0) * 0.05, seed: 1).eyesOpen }
        let b = (0..<60).map { f(.waitingForApproval, Double($0) * 0.05, seed: 2).eyesOpen }
        XCTAssertNotEqual(a, b)
    }

    func testWaitingEyeScheduleIsDeterministicAndBounded() {
        let first = (0..<80).map { f(.waitingForApproval, Double($0) * 0.05, seed: 7).eyesOpen }
        let again = (0..<80).map { f(.waitingForApproval, Double($0) * 0.05, seed: 7).eyesOpen }
        XCTAssertEqual(first, again, "same seed and time must give the same frame")
        XCTAssertTrue(first.contains(true) && first.contains(false), "the eyes actually move")
    }

    func testDoneBlinkAndCursor() {
        XCTAssertFalse(f(.done, 0.1).eyesOpen)
        XCTAssertTrue(f(.done, 0.4).eyesOpen)
        XCTAssertFalse(f(.done, 2.5).eyesOpen, "blink repeats every 2.4 s")
        XCTAssertFalse(f(.done, 0.2).cursorOn, "first on-phase starts at 0.75 s")
        XCTAssertTrue(f(.done, 1.0).cursorOn)
        XCTAssertEqual(f(.done, 1.0).glyph, .cursor)
    }

    func testReduceMotionIsStatic() {
        let a = SpriteAnimator.frame(status: .working, elapsed: 0.0, seed: 1, reduceMotion: true)
        let b = SpriteAnimator.frame(status: .working, elapsed: 7.3, seed: 1, reduceMotion: true)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.bodyFrame, 0)
        let waiting = SpriteAnimator.frame(status: .waitingForApproval, elapsed: 9, seed: 1, reduceMotion: true)
        XCTAssertEqual(waiting.glyph, .question, "the glyph still says what it needs, it just does not move")
        XCTAssertFalse(waiting.glyphRaised)
    }

    func testFailedIsStaticClosedEyes() {
        XCTAssertFalse(f(.failed, 3).eyesOpen)
        XCTAssertNil(f(.failed, 3).glyph)
        XCTAssertEqual(f(.failed, 3).bodyFrame, 0)
    }

    func testNegativeElapsedBehavesLikeZero() {
        XCTAssertEqual(f(.working, -5).bodyFrame, 0, "a clock skew must not crash or show a negative frame")
        XCTAssertEqual(f(.done, -1), f(.done, 0))
        XCTAssertEqual(f(.waitingForApproval, -1), f(.waitingForApproval, 0))
    }
}
