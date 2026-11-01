import XCTest
@testable import ReefCore

final class NotchMachineTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 5_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func testHoverNeedsDwell() {
        var m = NotchMachine(timing: NotchTiming())
        XCTAssertEqual(m.apply(.hoverEnter(at(0))), .closed)
        XCTAssertEqual(m.nextDeadline, at(0.15))
        XCTAssertEqual(m.apply(.tick(at(0.1))), .closed)
        XCTAssertEqual(m.apply(.tick(at(0.2))), .transient(kind: .hover, until: .distantFuture))
    }

    func testHoverExitCollapsesAfterLeaveDelay() {
        var m = NotchMachine(timing: NotchTiming())
        _ = m.apply(.hoverEnter(at(0))); _ = m.apply(.tick(at(0.2)))
        XCTAssertEqual(m.apply(.hoverExit(at(1))), .transient(kind: .hover, until: at(1)))
        XCTAssertEqual(m.apply(.tick(at(1))), .closed)
    }

    func testHoverExitThenReenterCancelsCollapse() {
        var timing = NotchTiming(); timing.leaveCollapse = 1
        var m = NotchMachine(timing: timing)
        _ = m.apply(.hoverEnter(at(0))); _ = m.apply(.tick(at(0.2)))
        _ = m.apply(.hoverExit(at(1)))
        XCTAssertEqual(m.apply(.hoverEnter(at(1.5))), .transient(kind: .hover, until: .distantFuture))
        XCTAssertEqual(m.apply(.tick(at(3))), .transient(kind: .hover, until: .distantFuture))
    }

    func testQuestionIgnoresMouseLeaveAndOutsideClick() {
        var m = NotchMachine(timing: NotchTiming())
        m.pendingCount = 1
        XCTAssertEqual(m.apply(.present(.question(requestID: "q"), reason: .blockingRequest, at: at(0))), .blocking)
        XCTAssertEqual(m.apply(.hoverExit(at(1))), .blocking)
        XCTAssertEqual(m.apply(.outsideClick(at(2))), .blocking)
        XCTAssertEqual(m.apply(.tick(at(100))), .blocking)
    }

    func testCompletionAutoCollapsesAfterDwell() {
        var m = NotchMachine(timing: NotchTiming())
        XCTAssertEqual(m.apply(.taskComplete(at(0))), .transient(kind: .completion, until: at(5)))
        XCTAssertEqual(m.apply(.tick(at(4.9))), .transient(kind: .completion, until: at(5)))
        XCTAssertEqual(m.apply(.tick(at(5.1))), .closed)
    }

    func testBlockingSurfaceIgnoresEscapeUntilResolved() {
        var m = NotchMachine(timing: NotchTiming())
        m.pendingCount = 1
        _ = m.apply(.present(.approval(requestID: "r1"), reason: .blockingRequest, at: at(0)))
        XCTAssertEqual(m.apply(.escape(at(1))), .blocking)
    }

    func testClickToggles() {
        var m = NotchMachine(timing: NotchTiming())
        XCTAssertEqual(m.apply(.click(at(0))), .manualExpanded)
        XCTAssertEqual(m.apply(.click(at(1))), .closed)
    }

    func testRequestArrivedDoesNotOverrideManualExpanded() {
        var m = NotchMachine(timing: NotchTiming())
        _ = m.apply(.click(at(0)))
        m.pendingCount = 1
        XCTAssertEqual(m.apply(.requestArrived(at(1))), .manualExpanded)
    }

    func testRequestsClearedCollapsesOnlyWhenNoneLeft() {
        var m = NotchMachine(timing: NotchTiming())
        m.pendingCount = 2
        _ = m.apply(.requestArrived(at(0)))
        m.pendingCount = 1
        XCTAssertEqual(m.apply(.requestsCleared(at(1))), .blocking)
        m.pendingCount = 0
        XCTAssertEqual(m.apply(.requestsCleared(at(2))), .closed)
    }

    // MARK: - Stage 2: transition kinds and peek suspension

    func testHoverSuspendsACompletionPeekAndRestartsTheHold() {
        var timing = NotchTiming(); timing.leaveCollapse = 1
        var m = NotchMachine(timing: timing)
        _ = m.apply(.taskComplete(at(0)))
        _ = m.apply(.hoverEnter(at(1)))
        XCTAssertEqual(m.apply(.tick(at(30))), .transient(kind: .completion, until: .distantFuture))
        _ = m.apply(.hoverExit(at(31)))
        XCTAssertEqual(m.apply(.tick(at(31.9))), .transient(kind: .completion, until: at(32)))
        XCTAssertEqual(m.apply(.tick(at(32.1))), .closed)
    }

    func testPeekNeverReplacesABlockingPanel() {
        var m = NotchMachine(timing: NotchTiming())
        m.pendingCount = 1
        _ = m.apply(.requestArrived(at(0)))
        XCTAssertEqual(m.apply(.taskComplete(at(1))), .blocking)
        XCTAssertEqual(m.apply(.tick(at(10))), .blocking)
    }

    func testTransitionKindFollowsTheIntent() {
        var m = NotchMachine(timing: NotchTiming())
        _ = m.apply(.hoverEnter(at(0))); _ = m.apply(.tick(at(0.2)))
        XCTAssertEqual(m.lastTransition, .hoverExpand)
        m.pendingCount = 1
        _ = m.apply(.requestArrived(at(1)))
        XCTAssertEqual(m.lastTransition, .requestExpand)
        m.pendingCount = 0
        _ = m.apply(.requestsCleared(at(2)))
        XCTAssertEqual(m.lastTransition, .collapse)
        _ = m.apply(.taskComplete(at(3)))
        XCTAssertEqual(m.lastTransition, .peekExpand)
    }

    func testTransitionCurves() {
        XCTAssertEqual(NotchTransition.collapse.damping, 1.0)
        // The dwell belongs to the machine, which has already waited it by the time the state
        // changes; the view must not delay again. See testHoverDwellIsNotAppliedTwice.
        XCTAssertEqual(NotchTransition.hoverExpand.delay, 0)
        XCTAssertEqual(NotchTransition.requestExpand.revealDuration, Motion.autoRevealFadeDuration)
        XCTAssertEqual(NotchTransition.hoverExpand.revealDuration, Motion.headerFadeDuration)
        XCTAssertEqual(NotchTransition.snap.response, 0)
    }

    func testFailurePeekAlsoSuspendsOnHover() {
        var m = NotchMachine(timing: NotchTiming())
        _ = m.apply(.taskFailed(at(0)))
        _ = m.apply(.hoverEnter(at(1)))
        XCTAssertEqual(m.apply(.tick(at(20))), .transient(kind: .failure, until: .distantFuture))
    }

    func testNoAutoCollapseWhenSettingOff() {
        var timing = NotchTiming(); timing.autoCollapseOnLeave = false
        var m = NotchMachine(timing: timing)
        _ = m.apply(.hoverEnter(at(0))); _ = m.apply(.tick(at(0.2)))
        XCTAssertEqual(m.apply(.hoverExit(at(1))), .transient(kind: .hover, until: .distantFuture))
        XCTAssertEqual(m.apply(.outsideClick(at(2))), .closed)
    }

    func testSurfaceRoutingRecordsReasonAndStableID() {
        var m = NotchMachine(timing: NotchTiming())
        let key = SessionKey(source: .codex, sessionID: "s")
        XCTAssertEqual(m.apply(.present(.completion(key), reason: .completion, at: at(0))),
                       .transient(kind: .completion, until: at(5)))
        XCTAssertEqual(m.openReason, .completion)
        XCTAssertEqual(m.surface, .completion(key))
        _ = m.apply(.surfaceEntered(at(1)))
        XCTAssertTrue(m.notificationWasEntered)
        _ = m.apply(.tick(at(6)))
        XCTAssertNil(m.openReason)
        XCTAssertEqual(m.surface, .sessionList(actionableRequestID: nil))
    }

    func testQuestionAndPlanSurfacesPinAgainstOutsideClick() {
        for surface in [ReefSurface.question(requestID: "q"), .plan(requestID: "p")] {
            var m = NotchMachine(timing: NotchTiming())
            _ = m.apply(.present(surface, reason: .blockingRequest, at: at(0)))
            XCTAssertEqual(m.apply(.outsideClick(at(1))), .blocking)
        }
    }

    func testManualApprovalPlanAndCompletionCollapseOnPointerExit() {
        var manual = NotchMachine(timing: NotchTiming())
        _ = manual.apply(.click(at(0)))
        XCTAssertEqual(manual.apply(.hoverExit(at(1))), .closed)

        for surface in [ReefSurface.approval(requestID: "a"), .plan(requestID: "p")] {
            var action = NotchMachine(timing: NotchTiming())
            _ = action.apply(.present(surface, reason: .blockingRequest, at: at(0)))
            XCTAssertEqual(action.apply(.hoverExit(at(1))), .closed)
        }

        var completion = NotchMachine(timing: NotchTiming())
        _ = completion.apply(.taskComplete(at(0)))
        XCTAssertEqual(completion.apply(.hoverExit(at(1))),
                       .transient(kind: .completion, until: at(1)))
        XCTAssertEqual(completion.apply(.tick(at(1))), .closed)
    }
}
