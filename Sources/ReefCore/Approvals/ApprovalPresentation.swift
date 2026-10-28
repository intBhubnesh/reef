import Foundation

/// How an approval request is rendered: a command, a diff, a one-line summary, or raw JSON.
public enum ApprovalPresentation: Equatable {
    case bash(command: String, description: String?)
    case diff(path: String, lines: [DiffLine])
    case multiDiff([ApplyPatch.File])
    case summary(title: String, detail: String)
    case json(toolName: String, pretty: String)

    public static func make(toolName: String, toolInput: [String: Any], source: AgentSource,
                            readFile: (String) -> String?) -> ApprovalPresentation {
        switch toolName {
        case "Bash", "shell", "exec_command", "local_shell":
            return .bash(command: commandString(toolInput["command"] ?? toolInput["cmd"]),
                         description: toolInput["description"] as? String)
        case "Edit":
            let path = toolInput["file_path"] as? String ?? ""
            let old = toolInput["old_string"] as? String ?? ""
            let new = toolInput["new_string"] as? String ?? ""
            if let existing = readFile(path), let range = existing.range(of: old), !old.isEmpty {
                let updated = existing.replacingCharacters(in: range, with: new)
                return .diff(path: path, lines: LineDiff.compute(old: existing, new: updated))
            }
            return .diff(path: path, lines: LineDiff.compute(old: old, new: new))
        case "Write":
            let path = toolInput["file_path"] as? String ?? ""
            let content = toolInput["content"] as? String ?? ""
            return .diff(path: path, lines: LineDiff.compute(old: readFile(path) ?? "", new: content))
        case "MultiEdit":
            let path = toolInput["file_path"] as? String ?? ""
            var text = readFile(path) ?? ""
            let original = text
            for edit in toolInput["edits"] as? [[String: Any]] ?? [] {
                if let old = edit["old_string"] as? String, let new = edit["new_string"] as? String, let r = text.range(of: old) {
                    text.replaceSubrange(r, with: new)
                }
            }
            return .multiDiff([ApplyPatch.File(path: path, lines: LineDiff.compute(old: original, new: text))])
        case "apply_patch":
            let patch = (toolInput["patch"] as? String) ?? (toolInput["input"] as? String) ?? ""
            return .multiDiff(ApplyPatch.files(from: patch))
        case "Read", "Glob", "Grep", "WebFetch", "WebSearch":
            let detail = ["file_path", "pattern", "url", "query", "path"].lazy
                .compactMap { toolInput[$0] as? String }.first ?? ""
            return .summary(title: toolName, detail: detail)
        default:
            let data = (try? JSONSerialization.data(withJSONObject: toolInput, options: [.prettyPrinted, .sortedKeys])) ?? Data()
            return .json(toolName: toolName, pretty: String(data: data, encoding: .utf8) ?? "{}")
        }
    }

    private static func commandString(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if let parts = value as? [String] { return parts.joined(separator: " ") }
        return ""
    }
}
