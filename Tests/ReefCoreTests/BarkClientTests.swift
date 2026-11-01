import XCTest
@testable import ReefCore

final class BarkClientTests: XCTestCase {
    func testBuildsV2JSONRequestWithoutPuttingKeyInURL() throws {
        let request = try BarkClient.request(
            configuration: BarkConfiguration(serverURL: "https://api.day.app/", deviceKey: "secret-key"),
            message: BarkMessage(title: "Input needed", body: "reef needs approval", level: .timeSensitive,
                                 sound: "minuet")
        )
        XCTAssertEqual(request.url?.absoluteString, "https://api.day.app/push")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertFalse(request.url?.absoluteString.contains("secret-key") ?? true)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["device_key"] as? String, "secret-key")
        XCTAssertEqual(json["title"] as? String, "Input needed")
        XCTAssertEqual(json["body"] as? String, "reef needs approval")
        XCTAssertEqual(json["group"] as? String, "Reef")
        XCTAssertEqual(json["level"] as? String, "timeSensitive")
        XCTAssertEqual(json["sound"] as? String, "minuet")
    }

    func testPreservesSelfHostedPathAndDoesNotDoublePush() throws {
        let config = BarkConfiguration(serverURL: "http://bark.local:8080/notifications", deviceKey: "key")
        let request = try BarkClient.request(configuration: config, message: BarkMessage(title: "T", body: "B"))
        XCTAssertEqual(request.url?.absoluteString, "http://bark.local:8080/notifications/push")

        let push = BarkConfiguration(serverURL: "https://bark.example/push", deviceKey: "key")
        XCTAssertEqual(try BarkClient.request(configuration: push, message: BarkMessage(title: "T", body: "B")).url?.path,
                       "/push")
    }

    func testAcceptsTheCompleteTestURLCopiedByBark() throws {
        let config = BarkConfiguration(serverURL: "https://unused.example",
                                       deviceKey: "https://api.day.app/copied-key/Test/Message?group=test")
        let request = try BarkClient.request(configuration: config, message: BarkMessage(title: "T", body: "B"))
        XCTAssertEqual(request.url?.absoluteString, "https://api.day.app/push")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(json["device_key"] as? String, "copied-key")
    }

    func testRejectsMissingKeyAndUnsafeServerShape() {
        XCTAssertThrowsError(try BarkClient.request(
            configuration: BarkConfiguration(serverURL: "https://api.day.app", deviceKey: " "),
            message: BarkMessage(title: "T", body: "B")
        )) { XCTAssertEqual($0 as? BarkClientError, .missingDeviceKey) }
        XCTAssertThrowsError(try BarkClient.request(
            configuration: BarkConfiguration(serverURL: "file:///tmp/bark", deviceKey: "key"),
            message: BarkMessage(title: "T", body: "B")
        )) { XCTAssertEqual($0 as? BarkClientError, .invalidServerURL) }
    }
}
