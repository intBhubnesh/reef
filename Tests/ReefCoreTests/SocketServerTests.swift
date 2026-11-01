import XCTest
@testable import ReefCore

final class SocketServerTests: XCTestCase {
    var dir: URL!
    var path: String { dir.appendingPathComponent("reef.sock").path }
    var server: UnixSocketServer!
    let queue = DispatchQueue(label: "reef.test.server")

    override func setUp() {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("reef-sock-\(UUID().uuidString.prefix(8))")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        server = UnixSocketServer(path: path, queue: queue)
    }

    override func tearDown() {
        server.stop()
    }

    private func fireLine(_ name: String = "Stop") -> Data {
        try! BridgeRequest(id: "req-\(name)", mode: .fire, event: ["hook_event_name": name, "session_id": "s1"]).encodedLine()
    }
    private func waitLine(id: String = "req-wait") -> Data {
        try! BridgeRequest(id: id, mode: .wait, event: ["hook_event_name": "PermissionRequest", "session_id": "s1", "tool_name": "Bash"]).encodedLine()
    }

    func testFireRequestIsDeliveredAndConnectionClosed() throws {
        let received = expectation(description: "request")
        let closed = expectation(description: "closed")
        server.onRequest = { req, conn in
            XCTAssertEqual(req.mode, .fire)
            XCTAssertEqual(req.event["hook_event_name"] as? String, "Stop")
            conn.onClosed = { closed.fulfill() }
            received.fulfill()
        }
        try server.start()
        let client = UnixSocketClient(path: path)
        XCTAssertNil(try client.send(fireLine(), awaitReply: false, timeout: 1))
        wait(for: [received, closed], timeout: 2)
    }

    func testWaitRequestReceivesReply() throws {
        server.onRequest = { req, conn in
            let decision = DecisionEncoder.encode(.allow(), for: .claude)
            let reply = (try? JSONSerialization.jsonObject(with: decision)) as? [String: Any] ?? [:]
            conn.reply(BridgeResponse(id: req.id, reply: reply))
        }
        try server.start()
        let client = UnixSocketClient(path: path)
        let line = try XCTUnwrap(try client.send(waitLine(), awaitReply: true, timeout: 2))
        let response = try BridgeResponse.decode(line: line)
        XCTAssertEqual(response.id, "req-wait")
        let replyData = try JSONSerialization.data(withJSONObject: response.reply, options: [.sortedKeys])
        XCTAssertEqual(replyData, DecisionEncoder.encode(.allow(), for: .claude))
    }

    func testPeerCloseDropsPending() throws {
        let pending = PendingRequests()
        let dropped = expectation(description: "dropped")
        pending.onDropped = { id in XCTAssertEqual(id, "req-wait"); dropped.fulfill() }
        server.onRequest = { req, conn in
            pending.add(requestID: req.id, key: SessionKey(source: .claude, sessionID: "s1"), connection: conn, deadline: Date().addingTimeInterval(60))
        }
        try server.start()
        let client = UnixSocketClient(path: path)
        try client.connect()
        try client.sendRaw(waitLine())
        usleep(100_000)
        client.close()
        wait(for: [dropped], timeout: 2)
        XCTAssertEqual(pending.count, 0)
    }

    func testExpireReleasesWithNoDecision() throws {
        let pending = PendingRequests()
        server.onRequest = { req, conn in
            pending.add(requestID: req.id, key: SessionKey(source: .claude, sessionID: "s1"), connection: conn, deadline: Date().addingTimeInterval(-1))
            XCTAssertEqual(pending.expire(now: Date()), ["req-wait"])
        }
        try server.start()
        let client = UnixSocketClient(path: path)
        let line = try XCTUnwrap(try client.send(waitLine(), awaitReply: true, timeout: 2))
        XCTAssertEqual(try BridgeResponse.decode(line: line).reply.count, 0)
        XCTAssertEqual(pending.count, 0)
    }

    func testResolveSendsDecisionAndRemoves() throws {
        let pending = PendingRequests()
        let added = expectation(description: "added")
        server.onRequest = { req, conn in
            pending.add(requestID: req.id, key: SessionKey(source: .claude, sessionID: "s1"), connection: conn, deadline: Date().addingTimeInterval(60))
            added.fulfill()
        }
        try server.start()
        let client = UnixSocketClient(path: path)
        try client.connect()
        try client.sendRaw(waitLine())
        wait(for: [added], timeout: 2)
        XCTAssertEqual(pending.requestIDs(for: SessionKey(source: .claude, sessionID: "s1")), ["req-wait"])
        XCTAssertTrue(pending.resolve(requestID: "req-wait", decision: .deny(message: "no"), source: .claude))
        XCTAssertFalse(pending.resolve(requestID: "req-wait", decision: .deny(message: "no"), source: .claude))
        let line = try client.readLine(timeout: 2)
        let reply = try BridgeResponse.decode(line: line).reply
        let decision = (reply["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
        XCTAssertEqual(decision?["behavior"] as? String, "deny")
        XCTAssertEqual(pending.count, 0)
    }

    func testReleaseAllOnStop() throws {
        let pending = PendingRequests()
        let added = expectation(description: "added")
        server.onRequest = { req, conn in
            pending.add(requestID: req.id, key: SessionKey(source: .claude, sessionID: "s1"), connection: conn, deadline: Date().addingTimeInterval(60))
            added.fulfill()
        }
        try server.start()
        let client = UnixSocketClient(path: path)
        try client.connect()
        try client.sendRaw(waitLine())
        wait(for: [added], timeout: 2)
        pending.releaseAll()
        server.stop()
        let reply = try BridgeResponse.decode(line: try client.readLine(timeout: 2)).reply
        XCTAssertEqual(reply.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testSocketFileModeIs0600() throws {
        try server.start()
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        XCTAssertEqual((attrs[.posixPermissions] as? Int) ?? 0 & 0o777, 0o600)
    }

    func testSecondServerCannotStealALiveSocket() throws {
        try server.start()
        let replacement = UnixSocketServer(path: path, queue: DispatchQueue(label: "reef.test.replacement"))
        XCTAssertThrowsError(try replacement.start())

        let received = expectation(description: "original still receives")
        server.onRequest = { _, _ in received.fulfill() }
        XCTAssertNil(try UnixSocketClient(path: path).send(fireLine(), awaitReply: false, timeout: 1))
        wait(for: [received], timeout: 2)
        replacement.stop()
        XCTAssertTrue(FileManager.default.fileExists(atPath: path),
                      "a server that never owned the path must not unlink it")
    }

    func testStaleSocketPathIsReclaimed() throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes); raw[bytes.count] = 0
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, len) }
        }
        XCTAssertEqual(bound, 0)
        Darwin.close(fd) // leave the filesystem entry behind, as a crash would

        try server.start()
        XCTAssertNoThrow(try UnixSocketClient(path: path).connect())
    }

    func testTwoWaitRequestsAreIndependent() throws {
        let pending = PendingRequests()
        let added = expectation(description: "added"); added.expectedFulfillmentCount = 2
        server.onRequest = { req, conn in
            pending.add(requestID: req.id, key: SessionKey(source: .claude, sessionID: req.event["session_id"] as? String ?? ""), connection: conn, deadline: Date().addingTimeInterval(60))
            added.fulfill()
        }
        try server.start()
        let a = UnixSocketClient(path: path), b = UnixSocketClient(path: path)
        try a.connect(); try b.connect()
        try a.sendRaw(waitLine(id: "ra")); try b.sendRaw(waitLine(id: "rb"))
        wait(for: [added], timeout: 2)
        XCTAssertEqual(pending.count, 2)
        XCTAssertTrue(pending.resolve(requestID: "rb", decision: .allow(), source: .claude))
        XCTAssertEqual(try BridgeResponse.decode(line: try b.readLine(timeout: 2)).id, "rb")
        XCTAssertEqual(pending.count, 1)
        XCTAssertThrowsError(try a.readLine(timeout: 0.2))
    }
}
