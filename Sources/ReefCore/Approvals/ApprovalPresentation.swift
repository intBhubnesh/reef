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
                return .diff(path: path, lines: windowedDiff(existing: existing, range: range, replacement: new))
            }
            return .diff(path: path, lines: LineDiff.compute(old: old, new: new))
        case "Write":
            let path = toolInput["file_path"] as? String ?? ""
            let content = toolInput["content"] as? String ?? ""
            let existing = readFile(path) ?? ""
            let oldLines = lineCount(existing), newLines = lineCount(content)
            if max(oldLines, newLines) > maxDiffLines {
                return .summary(title: toolName, detail: "\(path) · \(newLines) lines (too large to diff, was \(oldLines))")
            }
            return .diff(path: path, lines: LineDiff.compute(old: existing, new: content))
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

    /// Above this many lines on either side a full LCS diff is too expensive to run on the main thread.
    public static let maxDiffLines = 2000
    static let windowRadius = 40

    static func lineCount(_ s: String) -> Int {
        s.isEmpty ? 0 : s.reduce(into: 1) { if $1 == "\n" { $0 += 1 } }
    }

    /// Diff only the lines around an Edit's match when the file is large, keeping absolute line numbers.
    static func windowedDiff(existing: String, range: Range<String.Index>, replacement: String) -> [DiffLine] {
        let updated = existing.replacingCharacters(in: range, with: replacement)
        guard lineCount(existing) > maxDiffLines else { return LineDiff.compute(old: existing, new: updated) }
        let oldLines = existing.components(separatedBy: "\n")
        let newLines = updated.components(separatedBy: "\n")
        let startLine = existing[..<range.lowerBound].filter { $0 == "\n" }.count
        let oldSpan = existing[range].filter { $0 == "\n" }.count
        let newSpan = replacement.filter { $0 == "\n" }.count
        let lo = max(0, startLine - windowRadius)
        let oldHi = min(oldLines.count, startLine + oldSpan + windowRadius + 1)
        let newHi = min(newLines.count, startLine + newSpan + windowRadius + 1)
        let windowed = LineDiff.compute(old: oldLines[lo..<oldHi].joined(separator: "\n"),
                                        new: newLines[lo..<newHi].joined(separator: "\n"))
        return windowed.map { DiffLine(kind: $0.kind, text: $0.text,
                                       oldNumber: $0.oldNumber.map { $0 + lo }, newNumber: $0.newNumber.map { $0 + lo }) }
    }

    private static func commandString(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if let parts = value as? [String] { return parts.joined(separator: " ") }
        return ""
    }
}
