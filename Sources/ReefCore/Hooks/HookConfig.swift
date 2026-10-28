import Foundation

/// Pure transforms over an agent's hook configuration JSON (`~/.claude/settings.json`, `~/.codex/hooks.json`).
public enum HookConfig {
    public static let bridgeMarker = "$HOME/.reef/bin/reef-bridge"
    public static let terminalTitleEnvKey = "CLAUDE_CODE_DISABLE_TERMINAL_TITLE"

    public static let claudeEvents = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest",
        "Notification", "Stop", "StopFailure", "SubagentStart", "SubagentStop", "SessionEnd", "PreCompact", "PostCompact",
    ]
    public static let codexEvents = [
        "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse",
        "PreCompact", "PostCompact", "SubagentStart", "SubagentStop", "Stop", "Interrupt",
    ]

    public static func events(for source: AgentSource) -> [String] {
        source == .claude ? claudeEvents : codexEvents
    }

    public static func command(source: AgentSource) -> String {
        "/bin/sh -c '[ -x \"\(bridgeMarker)\" ] && \"\(bridgeMarker)\" --source \(source.rawValue); exit 0'"
    }

    public static func timeout(event: String, source: AgentSource) -> Int {
        if event == "PermissionRequest" { return 3600 }
        if source == .codex, event == "SessionEnd" || event == "Interrupt" { return 1 }
        return 5
    }

    public static func matcher(event: String, source: AgentSource) -> String? {
        switch source {
        case .claude:
            return ["PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest"].contains(event) ? "*" : nil
        case .codex:
            switch event {
            case "SessionStart": return "startup|resume|clear"
            case "PreCompact", "PostCompact": return "manual|auto"
            default: return nil
            }
        }
    }

    public struct HookStatus: Equatable {
        public let installedEvents: [String]
        public let missingEvents: [String]
        public var isComplete: Bool { missingEvents.isEmpty }
    }

    public static func install(into root: [String: Any], source: AgentSource) -> [String: Any] {
        var root = root
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in events(for: source) {
            var entries = hooks[event] as? [[String: Any]] ?? []
            guard !entries.contains(where: isOurs) else { continue }
            let hook: [String: Any] = ["type": "command", "command": command(source: source),
                                       "timeout": timeout(event: event, source: source)]
            var entry: [String: Any] = ["hooks": [hook]]
            if let matcher = matcher(event: event, source: source) { entry["matcher"] = matcher }
            entries.append(entry)
            hooks[event] = entries
        }
        root["hooks"] = hooks
        if source == .claude {
            var env = root["env"] as? [String: String] ?? [:]
            if env[terminalTitleEnvKey] == nil { env[terminalTitleEnvKey] = "1" }
            root["env"] = env
        }
        return root
    }

    public static func uninstall(from root: [String: Any], source: AgentSource) -> [String: Any] {
        var root = root
        guard var hooks = root["hooks"] as? [String: Any] else { return root }
        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries.removeAll(where: isOurs)
            hooks[event] = entries.isEmpty ? nil : entries
        }
        root["hooks"] = hooks
        return root
    }

    public static func status(of root: [String: Any], source: AgentSource) -> HookStatus {
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        let wanted = events(for: source)
        let installed = wanted.filter { (hooks[$0] as? [[String: Any]] ?? []).contains(where: isOurs) }
        return HookStatus(installedEvents: installed, missingEvents: wanted.filter { !installed.contains($0) })
    }

    /// An entry is ours when any of its hooks runs the Reef bridge.
    static func isOurs(_ entry: [String: Any]) -> Bool {
        (entry["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String ?? "").contains(bridgeMarker) }
    }
}
