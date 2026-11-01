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
        "SessionStart", "UserPromptSubmit", "PermissionRequest", "Stop",
    ]

    public static func events(for source: AgentSource) -> [String] {
        source == .claude ? claudeEvents : codexEvents
    }

    public static func command(source: AgentSource) -> String {
        "/bin/sh -c '[ -x \"\(bridgeMarker)\" ] && \"\(bridgeMarker)\" --source \(source.rawValue); exit 0'"
    }

    public static func timeout(event: String, source: AgentSource) -> Int {
        if event == "PermissionRequest" { return source == .claude ? 86_400 : 3_600 }
        if source == .codex, event == "SessionEnd" || event == "Interrupt" { return 1 }
        return 45
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
        public let staleEvents: [String]
        public let obsoleteEvents: [String]
        public var isComplete: Bool { missingEvents.isEmpty && staleEvents.isEmpty && obsoleteEvents.isEmpty }
    }

    public static func install(into root: [String: Any], source: AgentSource) -> [String: Any] {
        var root = root
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let wanted = Set(events(for: source))
        // Migrate older Reef installs that registered a noisier event set. Only Reef-owned
        // entries are removed; entries from the user and other applications remain untouched.
        for (event, value) in hooks where !wanted.contains(event) {
            guard var entries = value as? [[String: Any]] else { continue }
            entries.removeAll(where: isOurs)
            hooks[event] = entries.isEmpty ? nil : entries
        }
        for event in events(for: source) {
            var entries = hooks[event] as? [[String: Any]] ?? []
            if entries.contains(where: { isCurrent($0, event: event, source: source) }) { continue }
            entries.removeAll(where: isOurs)
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
        let owned = wanted.filter { (hooks[$0] as? [[String: Any]] ?? []).contains(where: isOurs) }
        let installed = wanted.filter { event in
            (hooks[event] as? [[String: Any]] ?? []).contains { isCurrent($0, event: event, source: source) }
        }
        let obsolete = hooks.compactMap { event, value -> String? in
            guard !wanted.contains(event),
                  (value as? [[String: Any]] ?? []).contains(where: isOurs) else { return nil }
            return event
        }.sorted()
        return HookStatus(installedEvents: owned,
                          missingEvents: wanted.filter { !owned.contains($0) },
                          staleEvents: owned.filter { !installed.contains($0) },
                          obsoleteEvents: obsolete)
    }

    /// An entry is ours when any of its hooks runs the Reef bridge.
    static func isOurs(_ entry: [String: Any]) -> Bool {
        (entry["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String ?? "").contains(bridgeMarker) }
    }

    static func isCurrent(_ entry: [String: Any], event: String, source: AgentSource) -> Bool {
        guard let hooks = entry["hooks"] as? [[String: Any]], hooks.count == 1,
              let hook = hooks.first,
              hook["command"] as? String == command(source: source),
              hook["timeout"] as? Int == timeout(event: event, source: source)
        else { return false }
        return (entry["matcher"] as? String) == matcher(event: event, source: source)
    }
}
