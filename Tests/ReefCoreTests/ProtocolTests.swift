import XCTest
@testable import ReefCore

final class ProtocolTests: XCTestCase {
    func testRequestRoundTrip() throws {
        let req = BridgeRequest(id: "abc", mode: .wait, event: ["session_id": "s1", "text": "line1\nline2"])
        let line = try req.encodedLine()
        XCTAssertEqual(line.last, UInt8(ascii: "\n"))
        XCTAssertEqual(line.filter { $0 == UInt8(ascii: "\n") }.count, 1)
        let back = try BridgeRequest.decode(line: line)
        XCTAssertEqual(back.id, "abc")
        XCTAssertEqual(back.mode, .wait)
        XCTAssertEqual(back.v, 1)
        XCTAssertEqual(back.event["session_id"] as? String, "s1")
        XCTAssertEqual(back.event["text"] as? String, "line1\nline2")
    }

    func testResponseRoundTrip() throws {
        let resp = BridgeResponse(id: "abc", reply: ["ok": true])
        let back = try BridgeResponse.decode(line: try resp.encodedLine())
        XCTAssertEqual(back.id, "abc")
        XCTAssertEqual(back.reply["ok"] as? Bool, true)
    }

    func testFramerSplitsAndBuffers() {
        let framer = LineFramer()
        let first = framer.append("{\"a\":1}\n{\"b\"".data(using: .utf8)!)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(String(data: first[0], encoding: .utf8), "{\"a\":1}")
        let second = framer.append(":2}\n".data(using: .utf8)!)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(String(data: second[0], encoding: .utf8), "{\"b\":2}")
    }

    func testModeForEvent() {
        XCTAssertEqual(BridgeMode.forEvent(name: "PermissionRequest"), .wait)
        XCTAssertEqual(BridgeMode.forEvent(name: "Stop"), .fire)
        XCTAssertEqual(BridgeMode.forEvent(name: "PreToolUse"), .fire)
    }

    func testDecodeRejectsWrongVersion() {
        let bad = #"{"v":2,"id":"x","mode":"fire","event":{}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try BridgeRequest.decode(line: bad))
    }
}
