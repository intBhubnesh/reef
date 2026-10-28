import XCTest
@testable import ReefCore

final class NotchGeometryTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1710, height: 1107)

    func testNotchFromAuxAreas() {
        let g = NotchGeometry.compute(screen: screen, safeTop: 33,
                                      auxLeft: CGRect(x: 0, y: 1074, width: 763, height: 33),
                                      auxRight: CGRect(x: 948, y: 1074, width: 762, height: 33))
        XCTAssertEqual(g.notchRect, CGRect(x: 763, y: 0, width: 185, height: 33))
        XCTAssertEqual(g.pillRect, CGRect(x: 731, y: 0, width: 249, height: 33))
        XCTAssertEqual(g.panelRect.width, 648)
        XCTAssertEqual(g.panelRect.midX, 855.5, accuracy: 0.5)
        XCTAssertEqual(g.panelRect.minY, 0)
        XCTAssertEqual(g.panelRect.height, 580)
    }

    func testSyntheticIslandWithoutNotch() {
        let g = NotchGeometry.compute(screen: screen, safeTop: 0, auxLeft: nil, auxRight: nil)
        XCTAssertEqual(g.notchRect.width, 185)
        XCTAssertEqual(g.notchRect.height, 33)
        XCTAssertEqual(g.notchRect.midX, 855, accuracy: 0.5)
        XCTAssertEqual(g.pillRect.width, 249)
        XCTAssertGreaterThan(g.pillRect.width, 0)
    }

    func testPanelClampsToNarrowScreen() {
        let g = NotchGeometry.compute(screen: CGRect(x: 0, y: 0, width: 600, height: 400), safeTop: 0, auxLeft: nil, auxRight: nil)
        XCTAssertEqual(g.panelRect.width, 568)
        XCTAssertEqual(g.panelRect.height, 400 - 16)
    }

    func testPillHeightNeverBelowThirtyThree() {
        let g = NotchGeometry.compute(screen: screen, safeTop: 20,
                                      auxLeft: CGRect(x: 0, y: 1087, width: 700, height: 20),
                                      auxRight: CGRect(x: 900, y: 1087, width: 810, height: 20))
        XCTAssertEqual(g.pillRect.height, 33)
        XCTAssertEqual(g.notchRect.width, 200)
    }
}
