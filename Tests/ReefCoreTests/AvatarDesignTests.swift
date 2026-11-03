import CoreGraphics
import XCTest
@testable import ReefCore

final class AvatarDesignTests: XCTestCase {
    func testCatalogueContainsOrbAndTwentyTwoObjectDesigns() {
        XCTAssertEqual(AvatarDesign.catalog.count, 23)
        XCTAssertEqual(AvatarDesign.catalog.first?.id, AvatarDesign.orb.id)
        XCTAssertEqual(Set(AvatarDesign.catalog.map(\.id)).count, AvatarDesign.catalog.count)
        XCTAssertEqual(AvatarDesign.catalog.dropFirst().filter { $0.bodyPath != nil }.count, 22)
    }

    func testEveryObjectPathFitsTheAvatarViewBoxAndCarriesUsableEyes() {
        for design in AvatarDesign.catalog.dropFirst() {
            guard let path = design.bodyPath else {
                return XCTFail("Missing path for \(design.id)")
            }
            let bounds = path.boundingBoxOfPath
            XCTAssertGreaterThanOrEqual(bounds.minX, 0, design.id)
            XCTAssertGreaterThanOrEqual(bounds.minY, 0, design.id)
            XCTAssertLessThanOrEqual(bounds.maxX, 100, design.id)
            XCTAssertLessThanOrEqual(bounds.maxY, 100, design.id)
            XCTAssertTrue(bounds.width > 30 && bounds.height > 30, design.id)
            XCTAssertTrue((0...100).contains(design.eyes.x), design.id)
            XCTAssertTrue((0...100).contains(design.eyes.y), design.id)
            XCTAssertGreaterThan(design.eyeSpacing, 0, design.id)
        }
    }

    func testParserSupportsRelativeCommandsAndEllipticalArcs() throws {
        let relative = try SVGPathParser.path("m10 10h20v20h-20z")
        XCTAssertEqual(relative.boundingBoxOfPath, CGRect(x: 10, y: 10, width: 20, height: 20))

        let arc = try SVGPathParser.path("M10 50A40 20 25 0 1 90 50")
        XCTAssertGreaterThan(arc.boundingBoxOfPath.width, 79)
        XCTAssertGreaterThan(arc.boundingBoxOfPath.height, 20)
    }

    func testUnknownPersistedDesignFallsBackToOrb() {
        XCTAssertTrue(AvatarDesign.resolve("not-a-design").isOrb)
        XCTAssertEqual(AvatarDesign.resolve("ghost").title, "Ghost")
    }
}
