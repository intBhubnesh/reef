import XCTest
@testable import ReefCore

final class HookEventTests: XCTestCase {
    func testParsesPermissionRequest() throws {
        let json = """
        {"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"/tmp/p","tool_name":"Bash",
         "tool_input":{"command":"ls"},"tool_use_id":"tu1","permission_suggestions":[{"type":"addRules"}]}
        """.data(using: .utf8)!
        let e = try HookEvent.parse(source: .claude, data: json)
        XCTAssertEqual(e.name, "PermissionRequest")
        XCTAssertEqual(e.sessionID, "s1")
        XCTAssertEqual(e.cwd, "/tmp/p")
        XCTAssertEqual(e.toolName, "Bash")
        XCTAssertEqual(e.toolInput?["command"] as? String, "ls")
        XCTAssertEqual(e.toolUseID, "tu1")
        XCTAssertEqual(e.permissionSuggestions?.count, 1)
        XCTAssertEqual(e.source, .claude)
    }

    func testMissingSessionIDThrows() {
        let json = #"{"hook_event_name":"Stop"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try HookEvent.parse(source: .codex, data: json))
    }

    func testStopCarriesLastAssistantMessageAndPrompt() throws {
        let json = #"{"hook_event_name":"Stop","session_id":"s1","last_assistant_message":"done","prompt":"fix it"}"#
            .data(using: .utf8)!
        let e = try HookEvent.parse(source: .claude, data: json)
        XCTAssertEqual(e.lastAssistantMessage, "done")
        XCTAssertEqual(e.prompt, "fix it")
        XCTAssertNil(e.toolName)
    }

    func testNonObjectJSONThrows() {
        XCTAssertThrowsError(try HookEvent.parse(source: .claude, data: "[]".data(using: .utf8)!))
        XCTAssertThrowsError(try HookEvent.parse(source: .claude, data: "not json".data(using: .utf8)!))
    }
}
