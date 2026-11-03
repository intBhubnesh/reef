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
        XCTAssertEqual(s.preferredDisplayID, "automatic")
        XCTAssertFalse(s.muted)
        XCTAssertFalse(s.showHeadless)
        XCTAssertTrue(s.soundStarted && s.soundActionCompleted)
        XCTAssertTrue(s.soundInputNeeded && s.soundDone && s.soundFailed)
        XCTAssertFalse(s.barkEnabled)
        XCTAssertEqual(s.barkServerURL, "https://api.day.app")
        XCTAssertTrue(s.barkNotifyInputNeeded && s.barkNotifyDone && s.barkNotifyFailed)
        XCTAssertEqual(s.barkNotificationLevel, .active)
        XCTAssertEqual(s.avatarEmotionByStatus, AvatarStatusSlot.defaultMapping)
        XCTAssertEqual(s.avatarDesignID, AvatarDesign.orb.id)
    }

    func testRoundTrip() throws {
        var s = ReefSettings()
        s.hoverDelay = 0.4; s.muted = true; s.showBranch = false; s.panelMaxWidth = 500
        s.barkEnabled = true; s.barkServerURL = "https://bark.example"; s.barkLevel = "timeSensitive"
        s.avatarEmotionByStatus[AvatarStatusSlot.done.rawValue] = AvatarEmotion.laughing.rawValue
        s.avatarDesignID = "ghost"
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
        XCTAssertEqual(t.leaveCollapse, 0)
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
        XCTAssertEqual(s.avatarEmotionByStatus, AvatarStatusSlot.defaultMapping)
    }

    func testLegacyInstalledHooksMigrateToExplicitIntent() throws {
        let url = tempURL()
        try #"{"hooksInstalledByUser":["claude"]}"#.data(using: .utf8)!.write(to: url)
        let settings = ReefSettings.load(from: url)
        XCTAssertEqual(settings.hookIntent(for: .claude), .installed)
        XCTAssertEqual(settings.hookIntent(for: .codex), .untouched)
    }
}
