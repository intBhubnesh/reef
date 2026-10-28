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
        XCTAssertEqual(m.apply(.hoverExit(at(1))), .transient(kind: .hover, until: at(2)))
        XCTAssertEqual(m.apply(.tick(at(1.5))), .transient(kind: .hover, until: at(2)))
        XCTAssertEqual(m.apply(.tick(at(2.1))), .closed)
    }

    func testHoverExitThenReenterCancelsCollapse() {
        var m = NotchMachine(timing: NotchTiming())
        _ = m.apply(.hoverEnter(at(0))); _ = m.apply(.tick(at(0.2)))
        _ = m.apply(.hoverExit(at(1)))
        XCTAssertEqual(m.apply(.hoverEnter(at(1.5))), .transient(kind: .hover, until: .distantFuture))
        XCTAssertEqual(m.apply(.tick(at(3))), .transient(kind: .hover, until: .distantFuture))
    }

    func testBlockingIgnoresMouseLeaveAndOutsideClick() {
        var m = NotchMachine(timing: NotchTiming())
        m.pendingCount = 1
        XCTAssertEqual(m.apply(.requestArrived(at(0))), .blocking)
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

    func testEscapeCollapsesBlocking() {
        var m = NotchMachine(timing: NotchTiming())
        m.pendingCount = 1
        _ = m.apply(.requestArrived(at(0)))
        XCTAssertEqual(m.apply(.escape(at(1))), .closed)
    }

    func testClickToggles() {
        var m = NotchMachine(timing: NotchTiming())
        XCTAssertEqual(m.apply(.click(at(0))), .manualExpanded)
        XCTAssertEqual(m.apply(.hoverExit(at(1))), .manualExpanded)
        XCTAssertEqual(m.apply(.click(at(2))), .closed)
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

    func testNoAutoCollapseWhenSettingOff() {
        var timing = NotchTiming(); timing.autoCollapseOnLeave = false
        var m = NotchMachine(timing: timing)
        _ = m.apply(.hoverEnter(at(0))); _ = m.apply(.tick(at(0.2)))
        XCTAssertEqual(m.apply(.hoverExit(at(1))), .transient(kind: .hover, until: .distantFuture))
        XCTAssertEqual(m.apply(.outsideClick(at(2))), .closed)
    }
}
