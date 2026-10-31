import XCTest
@testable import ReefCore

final class ReefSettingsTests: XCTestCase {
    private func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("reef-settings-\(UUID().uuidString).json")
    }

    func testDefaultsWhenFileMissing() {
        let s = ReefSettings.load(from: tempURL())
        XCTAssertEqual(s, ReefSettings())
        XCTAssertEqual(s.hoverDelay, 0.15)
        XCTAssertEqual(s.revealDwell, 5)
        XCTAssertEqual(s.idleCleanupHours, 2)
        XCTAssertEqual(s.panelMaxWidth, 648)
        XCTAssertEqual(s.panelMaxHeight, 580)
        XCTAssertFalse(s.muted)
        XCTAssertFalse(s.showHeadless)
        XCTAssertTrue(s.soundInputNeeded && s.soundDone && s.soundFailed)
    }

    func testRoundTrip() throws {
        var s = ReefSettings()
        s.hoverDelay = 0.4; s.muted = true; s.showBranch = false; s.panelMaxWidth = 500
        let url = tempURL()
        try s.save(to: url)
        XCTAssertEqual(ReefSettings.load(from: url), s)
    }

    func testNotchTimingMapsFields() {
        var s = ReefSettings()
        s.hoverDelay = 0.3; s.revealDwell = 8; s.autoCollapseOnLeave = false
        let t = s.notchTiming
        XCTAssertEqual(t.hoverDelay, 0.3)
        XCTAssertEqual(t.revealDwell, 8)
        XCTAssertFalse(t.autoCollapseOnLeave)
        XCTAssertEqual(t.leaveCollapse, 1)
    }

    func testWatchCodexTranscriptsDefaultsOnAndRoundTrips() throws {
        XCTAssertTrue(ReefSettings().watchCodexTranscripts)
        var s = ReefSettings()
        s.watchCodexTranscripts = false
        let url = tempURL()
        try s.save(to: url)
        XCTAssertFalse(ReefSettings.load(from: url).watchCodexTranscripts)
    }

    func testCorruptFileFallsBackToDefaults() throws {
        let url = tempURL()
        try "{not json".data(using: .utf8)!.write(to: url)
        XCTAssertEqual(ReefSettings.load(from: url), ReefSettings())
    }

    func testUnknownKeysAndMissingKeysAreTolerated() throws {
        let url = tempURL()
        try #"{"muted":true,"futureSetting":42}"#.data(using: .utf8)!.write(to: url)
        let s = ReefSettings.load(from: url)
        XCTAssertTrue(s.muted)
        XCTAssertEqual(s.hoverDelay, 0.15)
    }
}
