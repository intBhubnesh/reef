import XCTest
@testable import ReefCore

final class HookConfigTests: XCTestCase {
    let expectedClaudeCommand = "/bin/sh -c '[ -x \"$HOME/.reef/bin/reef-bridge\" ] && \"$HOME/.reef/bin/reef-bridge\" --source claude; exit 0'"

    private func entries(_ root: [String: Any], _ event: String) -> [[String: Any]] {
        ((root["hooks"] as? [String: Any])?[event] as? [[String: Any]]) ?? []
    }
    private func hook(_ root: [String: Any], _ event: String, index: Int = 0) -> [String: Any] {
        (entries(root, event)[index]["hooks"] as? [[String: Any]])?.first ?? [:]
    }

    func testInstallAddsAllClaudeEventsWithExactCommandAndTimeouts() {
        let root = HookConfig.install(into: [:], source: .claude)
        for event in HookConfig.claudeEvents {
            XCTAssertEqual(entries(root, event).count, 1, event)
            XCTAssertEqual(hook(root, event)["command"] as? String, expectedClaudeCommand, event)
            XCTAssertEqual(hook(root, event)["type"] as? String, "command")
        }
        XCTAssertEqual(hook(root, "PermissionRequest")["timeout"] as? Int, 3600)
        XCTAssertEqual(hook(root, "Stop")["timeout"] as? Int, 5)
        XCTAssertEqual(entries(root, "PreToolUse")[0]["matcher"] as? String, "*")
        XCTAssertNil(entries(root, "Stop")[0]["matcher"])
    }

    func testInstallIsIdempotent() {
        let once = HookConfig.install(into: [:], source: .claude)
        let twice = HookConfig.install(into: once, source: .claude)
        XCTAssertTrue(NSDictionary(dictionary: once).isEqual(to: twice))
    }

    func testInstallPreservesOtherApps() {
        let other: [String: Any] = ["hooks": [["type": "command", "command": "'/Applications/boringNotch' --source claude", "timeout": 45]]]
        let root = HookConfig.install(into: ["hooks": ["Stop": [other]], "permissions": ["allow": ["Bash"]]], source: .claude)
        XCTAssertEqual(entries(root, "Stop").count, 2)
        XCTAssertEqual(hook(root, "Stop", index: 0)["command"] as? String, "'/Applications/boringNotch' --source claude")
        XCTAssertEqual(hook(root, "Stop", index: 1)["command"] as? String, expectedClaudeCommand)
        XCTAssertEqual((root["permissions"] as? [String: Any])?["allow"] as? [String], ["Bash"])
    }

    func testUninstallRemovesOnlyOurs() {
        let other: [String: Any] = ["hooks": [["type": "command", "command": "'/Applications/boringNotch' --source claude", "timeout": 45]]]
        let installed = HookConfig.install(into: ["hooks": ["Stop": [other]]], source: .claude)
        let root = HookConfig.uninstall(from: installed, source: .claude)
        XCTAssertEqual(entries(root, "Stop").count, 1)
        XCTAssertNil((root["hooks"] as? [String: Any])?["PermissionRequest"])
        XCTAssertEqual((root["env"] as? [String: String])?["CLAUDE_CODE_DISABLE_TERMINAL_TITLE"], "1")
    }

    func testClaudeInstallSetsTerminalTitleEnv() {
        let root = HookConfig.install(into: ["env": ["FOO": "bar"]], source: .claude)
        XCTAssertEqual((root["env"] as? [String: String])?["CLAUDE_CODE_DISABLE_TERMINAL_TITLE"], "1")
        XCTAssertEqual((root["env"] as? [String: String])?["FOO"], "bar")
        XCTAssertNil(HookConfig.install(into: [:], source: .codex)["env"])
    }

    func testCodexMatchersAndOneSecondTimeouts() {
        let root = HookConfig.install(into: [:], source: .codex)
        XCTAssertEqual(hook(root, "SessionEnd")["timeout"] as? Int, 1)
        XCTAssertEqual(hook(root, "Interrupt")["timeout"] as? Int, 1)
        XCTAssertEqual(hook(root, "PermissionRequest")["timeout"] as? Int, 3600)
        XCTAssertEqual(entries(root, "SessionStart")[0]["matcher"] as? String, "startup|resume|clear")
        XCTAssertEqual(entries(root, "PreCompact")[0]["matcher"] as? String, "manual|auto")
        XCTAssertEqual(entries(root, "PostCompact")[0]["matcher"] as? String, "manual|auto")
        XCTAssertTrue((hook(root, "Stop")["command"] as? String ?? "").hasSuffix("--source codex; exit 0'"))
        XCTAssertNil((root["hooks"] as? [String: Any])?["Notification"])
    }

    func testStatusReportsMissing() {
        var root = HookConfig.install(into: [:], source: .claude)
        var hooks = root["hooks"] as! [String: Any]
        hooks["Stop"] = nil
        root["hooks"] = hooks
        let status = HookConfig.status(of: root, source: .claude)
        XCTAssertEqual(status.missingEvents, ["Stop"])
        XCTAssertFalse(status.isComplete)
        XCTAssertTrue(HookConfig.status(of: HookConfig.install(into: root, source: .claude), source: .claude).isComplete)
        XCTAssertEqual(HookConfig.status(of: [:], source: .claude).installedEvents, [])
    }

    func testCodexTrustParsesState() {
        let toml = """
        [hooks.state."/Users/x/.codex/hooks.json:permission_request:0:0"]
        trusted_hash = "sha256:ab"

        [hooks.state."/Users/x/.codex/hooks.json:stop:1:0"]
        trusted_hash = "sha256:cd"
        """
        let path = "/Users/x/.codex/hooks.json"
        XCTAssertEqual(CodexTrust.isTrusted(hooksJSONPath: path, event: "PermissionRequest", entryIndex: 0, configTOML: toml), true)
        XCTAssertEqual(CodexTrust.isTrusted(hooksJSONPath: path, event: "PermissionRequest", entryIndex: 1, configTOML: toml), false,
                       "another app's trusted entry must not count for ours")
        XCTAssertEqual(CodexTrust.isTrusted(hooksJSONPath: path, event: "Stop", entryIndex: 1, configTOML: toml), true)
        XCTAssertEqual(CodexTrust.isTrusted(hooksJSONPath: path, event: "SessionStart", entryIndex: 0, configTOML: toml), false)
        XCTAssertNil(CodexTrust.isTrusted(hooksJSONPath: path, event: "Stop", entryIndex: 1, configTOML: "[mcp_servers.x]\nurl = \"y\""))
        XCTAssertEqual(CodexTrust.trustedCommands(configTOML: toml).count, 2)
        let root = HookConfig.install(into: ["hooks": ["Stop": [["hooks": [["type": "command", "command": "other"]]]]]], source: .codex)
        XCTAssertEqual(CodexTrust.ourEntryIndex(in: root, event: "Stop"), 1)
        XCTAssertEqual(CodexTrust.ourEntryIndex(in: root, event: "PermissionRequest"), 0)
        XCTAssertNil(CodexTrust.ourEntryIndex(in: [:], event: "Stop"))
    }
}
