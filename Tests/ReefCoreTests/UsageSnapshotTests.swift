import XCTest
@testable import ReefCore

final class UsageSnapshotTests: XCTestCase {
    private func data(_ s: String) -> Data { s.data(using: .utf8)! }

    func testParsesBothWindows() {
        let json = #"{"five_hour":{"used_percentage":21,"resets_at":"2026-10-31T12:00:00Z"},"seven_day":{"used_percentage":28}}"#
        let s = UsageSnapshot.parse(data(json), now: Date())!
        XCTAssertEqual(s.fiveHour?.usedPercent, 21)
        XCTAssertEqual(s.sevenDay?.usedPercent, 28)
        XCTAssertNotNil(s.fiveHour?.resetsAt)
        XCTAssertNil(s.sevenDay?.resetsAt)
    }

    func testMissingWindowDoesNotFailTheOther() {
        let s = UsageSnapshot.parse(data(#"{"five_hour":{"used_percentage":5}}"#), now: Date())!
        XCTAssertNotNil(s.fiveHour)
        XCTAssertNil(s.sevenDay)
    }

    func testMalformedAndEmptyReturnNil() {
        XCTAssertNil(UsageSnapshot.parse(data("not json"), now: Date()))
        XCTAssertNil(UsageSnapshot.parse(Data(), now: Date()))
        XCTAssertNil(UsageSnapshot.parse(data("[]"), now: Date()))
        XCTAssertNil(UsageSnapshot.parse(data("{}"), now: Date()), "no windows at all is not a snapshot")
    }

    func testStalenessAtTenMinutes() {
        let now = Date()
        let s = UsageSnapshot.parse(data(#"{"five_hour":{"used_percentage":5}}"#), now: now.addingTimeInterval(-601))!
        XCTAssertTrue(s.isStale(now: now))
        XCTAssertFalse(s.isStale(now: now, maxAge: 1200))
    }

    func testRemainingIsHumanReadable() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let json = #"{"five_hour":{"used_percentage":21,"resets_at":"RESET"}}"#
            .replacingOccurrences(of: "RESET", with: ISO8601DateFormatter().string(from: now.addingTimeInterval(3 * 3600 + 9 * 60)))
        let s = UsageSnapshot.parse(data(json), now: now)!
        XCTAssertEqual(s.fiveHour?.remaining(now: now), "3h9m")
        let past = UsageSnapshot.parse(data(#"{"five_hour":{"used_percentage":99,"resets_at":"1970-01-01T00:00:00Z"}}"#), now: now)!
        XCTAssertNil(past.fiveHour?.remaining(now: now), "a reset in the past shows nothing rather than a negative time")
    }

    func testAcceptsRateLimitsWrapper() {
        // The status line hands Reef the whole payload; the shim stores `rate_limits` but a
        // future shape change should not lose the data.
        let json = #"{"rate_limits":{"five_hour":{"used_percentage":7}}}"#
        XCTAssertEqual(UsageSnapshot.parse(data(json), now: Date())?.fiveHour?.usedPercent, 7)
    }

    // The real status-line payload: epoch seconds, fractional percentages, a model object,
    // and a spend-limit window. Verified against Claude Code's statusline reference.
    func testParsesTheRealStatusLinePayload() {
        let now = Date(timeIntervalSince1970: 1_738_420_000)
        let json = """
        {"model":{"id":"claude-opus-5-5","display_name":"Opus"},
         "rate_limits":{
           "five_hour":{"used_percentage":23.5,"resets_at":1738425600},
           "seven_day":{"used_percentage":41.2,"resets_at":1738857600},
           "spend_limit":{"used_percentage":62.8,"resets_at":1740787200,"used_usd":314.12,"limit_usd":500,"period":"monthly"}}}
        """
        let s = UsageSnapshot.parse(data(json), now: now)!
        XCTAssertEqual(s.fiveHour?.usedPercent, 23, "23.5 rounds down to a whole percent")
        XCTAssertEqual(s.sevenDay?.usedPercent, 41)
        XCTAssertEqual(s.spendLimit?.usedPercent, 62)
        XCTAssertEqual(s.modelName, "Opus")
        XCTAssertEqual(s.fiveHour?.remaining(now: now), "1h33m", "epoch resets_at is read as seconds")
    }

    func testModelIsOptionalAndDoesNotBlockParsing() {
        let s = UsageSnapshot.parse(data(#"{"rate_limits":{"seven_day":{"used_percentage":5}}}"#), now: Date())
        XCTAssertNotNil(s)
        XCTAssertNil(s?.modelName)
        XCTAssertNil(s?.spendLimit)
    }

    func testAModelAloneIsNotASnapshot() {
        XCTAssertNil(UsageSnapshot.parse(data(#"{"model":{"display_name":"Opus"}}"#), now: Date()),
                     "a model name with no limits is nothing to show")
    }

    func testStatusLineStateDetection() {
        XCTAssertEqual(StatusLineState.of(command: nil), .free)
        XCTAssertEqual(StatusLineState.of(command: ""), .free)
        XCTAssertEqual(StatusLineState.of(command: "/Users/x/.reef/bin/reef-statusline"), .ownedByReef)
        XCTAssertEqual(StatusLineState.of(command: "/Users/x/.vibe-island/bin/vibe-island-statusline"),
                       .ownedByOther("/Users/x/.vibe-island/bin/vibe-island-statusline"))
    }
}
