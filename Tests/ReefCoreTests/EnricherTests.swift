import XCTest
@testable import ReefCore

final class EnricherTests: XCTestCase {
    func testEnrichAddsReefObjectWithEnvSubset() {
        let env = ["PATH": "/usr/bin", "KITTY_WINDOW_ID": "7", "TMUX_PANE": "%2", "SECRET": "x"]
        let out = Enricher.enrich(event: ["hook_event_name": "Stop", "session_id": "s"], source: .claude, env: env,
                                  tty: "/dev/ttys001", pid: 10, ppid: 9, git: GitInfo(root: "/r/proj", branch: "main"), titleMarker: "reef:abcdefgh")
        let reef = out["reef"] as? [String: Any]
        XCTAssertEqual(reef?["tty"] as? String, "/dev/ttys001")
        XCTAssertEqual(reef?["pid"] as? Int, 10)
        XCTAssertEqual(reef?["ppid"] as? Int, 9)
        XCTAssertEqual(reef?["env"] as? [String: String], ["KITTY_WINDOW_ID": "7", "TMUX_PANE": "%2"])
        XCTAssertEqual((reef?["git"] as? [String: String])?["root"], "/r/proj")
        XCTAssertEqual((reef?["git"] as? [String: String])?["branch"], "main")
        XCTAssertEqual(reef?["title_marker"] as? String, "reef:abcdefgh")
        XCTAssertEqual(out["source"] as? String, "claude")
    }

    func testEnrichKeepsOriginalFieldsAndOmitsNils() {
        let out = Enricher.enrich(event: ["hook_event_name": "Stop", "session_id": "s", "cwd": "/x"], source: .codex, env: [:],
                                  tty: nil, pid: 1, ppid: 0, git: nil, titleMarker: nil)
        XCTAssertEqual(out["cwd"] as? String, "/x")
        let reef = out["reef"] as? [String: Any]
        XCTAssertNil(reef?["tty"]); XCTAssertNil(reef?["git"]); XCTAssertNil(reef?["title_marker"])
        XCTAssertEqual(reef?["env"] as? [String: String], [:])
    }

    func testTitleMarkerFormat() {
        XCTAssertEqual(TitleMarker.marker(sessionID: "abcdefghij"), "reef:abcdefgh")
        XCTAssertEqual(TitleMarker.marker(sessionID: "ab"), "reef:ab")
        let bytes = [UInt8](TitleMarker.oscTitle(project: "proj", marker: "reef:abcdefgh"))
        XCTAssertEqual(bytes.first, 0x1b)
        XCTAssertEqual(bytes.last, 0x07)
        XCTAssertEqual(String(bytes: bytes.dropFirst().dropLast(), encoding: .utf8), "]2;proj · reef:abcdefgh")
        XCTAssertEqual(String(bytes: [UInt8](TitleMarker.oscTitle(project: nil, marker: "reef:x")).dropFirst().dropLast(), encoding: .utf8), "]2;reef:x")
    }

    func testCLIPrintsEmptyObjectOnBadInput() {
        for input in ["not json", "[]", "", "{\"hook_event_name\":\"Stop\"}"] {
            var out = Data()
            let code = BridgeCLI.run(arguments: ["--source", "claude"], stdin: input.data(using: .utf8)!,
                                     env: ["HOME": NSTemporaryDirectory()], stdout: { out.append($0) })
            XCTAssertEqual(code, 0, input)
            XCTAssertEqual(String(data: out, encoding: .utf8), "{}\n", input)
        }
    }

    func testCLIWithoutSourcePrintsEmptyObject() {
        var out = Data()
        let code = BridgeCLI.run(arguments: [], stdin: "{}".data(using: .utf8)!, env: [:], stdout: { out.append($0) })
        XCTAssertEqual(code, 0)
        XCTAssertEqual(String(data: out, encoding: .utf8), "{}\n")
    }

    func testCLIFireEventWithoutAppPrintsEmptyObjectQuickly() {
        var out = Data()
        let start = Date()
        let home = NSTemporaryDirectory() + "reef-nohome-\(UUID().uuidString)"
        let code = BridgeCLI.run(arguments: ["--source", "codex"], stdin: "{\"hook_event_name\":\"Stop\",\"session_id\":\"s\"}".data(using: .utf8)!,
                                 env: ["HOME": home], stdout: { out.append($0) })
        XCTAssertEqual(code, 0)
        XCTAssertEqual(String(data: out, encoding: .utf8), "{}\n")
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.5)
    }
}
