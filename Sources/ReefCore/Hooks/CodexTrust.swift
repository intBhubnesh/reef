import Foundation

/// Reads Codex's hook trust registry as it appears in `~/.codex/config.toml`:
/// `[hooks.state."<hooks.json path>:<snake_event>:<entry index>:<hook index>"]` tables with a `trusted_hash`.
public enum CodexTrust {
    /// Every trusted table key (`<path>:<event>:<i>:<j>`), or empty when the section is absent.
    public static func trustedCommands(configTOML: String) -> Set<String> {
        var keys = Set<String>()
        for line in configTOML.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("[hooks.state.\""), trimmed.hasSuffix("\"]") else { continue }
            let start = trimmed.index(trimmed.startIndex, offsetBy: "[hooks.state.\"".count)
            let end = trimmed.index(trimmed.endIndex, offsetBy: -2)
            keys.insert(String(trimmed[start..<end]))
        }
        return keys
    }

    /// `nil` when config.toml has no `[hooks.state]` entries at all (cannot tell); else whether the entry at
    /// `entryIndex` under `event` has a trust record.
    public static func isTrusted(hooksJSONPath: String, event: String, entryIndex: Int, configTOML: String) -> Bool? {
        let keys = trustedCommands(configTOML: configTOML)
        guard !keys.isEmpty else { return nil }
        let prefix = "\(hooksJSONPath):\(snakeCase(event)):\(entryIndex):"
        return keys.contains { $0.hasPrefix(prefix) }
    }

    /// Position of Reef's entry in the event's array of a hooks.json root, if present.
    public static func ourEntryIndex(in root: [String: Any], event: String) -> Int? {
        let entries = (root["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
        return entries.firstIndex(where: HookConfig.isOurs)
    }

    static func snakeCase(_ event: String) -> String {
        var out = ""
        for (index, ch) in event.enumerated() {
            if ch.isUppercase, index > 0 { out.append("_") }
            out.append(ch.lowercased())
        }
        return out
    }
}
