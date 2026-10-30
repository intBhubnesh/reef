import XCTest
@testable import ReefCore

final class MotionTests: XCTestCase {
    func testMeasuredConstantsMatchTheSpec() {
        XCTAssertEqual(Motion.hoverDwell, 0.15)
        XCTAssertEqual(Motion.peekHold, 5.0)
        XCTAssertEqual(Motion.collapseDamping, 1.0, "collapse must not overshoot (M7)")
        XCTAssertGreaterThan(Motion.expandDamping, 0.7)
        XCTAssertLessThan(Motion.expandDamping, 0.9, "expand overshoots ~1.3% (M2)")
        XCTAssertEqual(Motion.spriteFramePeriod * Double(Motion.spriteCycleFrames), 1.2, accuracy: 0.001)
        XCTAssertEqual(Metrics.panelWidth, 648)
        XCTAssertEqual(Metrics.headerHeight, 36)
    }

    func testBobAndBlinkPeriodsMatchTheRecordings() {
        XCTAssertEqual(Motion.bobUp + Motion.bobDown, 0.88, accuracy: 0.001, "M15 bob period")
        XCTAssertEqual(Motion.cursorOn + Motion.cursorOff, 1.23, accuracy: 0.001, "M17 cursor period")
        XCTAssertEqual(Motion.blinkPeriod, 2.4, "M16")
        XCTAssertLessThan(Motion.blinkClosed, Motion.blinkPeriod)
    }

    func testRadiiComeFromTheDirectMeasurement() {
        XCTAssertEqual(Metrics.pillBottomRadius, 11)
        XCTAssertEqual(Metrics.panelBottomRadius, 18)
    }
}
