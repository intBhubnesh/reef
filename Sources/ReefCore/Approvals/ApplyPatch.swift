import Foundation

/// Parses Codex `apply_patch` text (`*** Begin Patch` … `*** End Patch`) into per-file diff lines.
public enum ApplyPatch {
    public struct File: Equatable {
        public let path: String
        public let lines: [DiffLine]
    }

    public static func files(from patch: String) -> [File] {
        var files: [File] = []
        var path: String?
        var lines: [DiffLine] = []
        var oldNumber = 0, newNumber = 0

        func flush() {
            if let path { files.append(File(path: path, lines: lines)) }
            path = nil; lines = []; oldNumber = 0; newNumber = 0
        }

        for raw in patch.components(separatedBy: "\n") {
            if raw.hasPrefix("*** Begin Patch") || raw.hasPrefix("*** End Patch") { continue }
            if raw.hasPrefix("*** Update File: ") || raw.hasPrefix("*** Add File: ") || raw.hasPrefix("*** Delete File: ") {
                flush()
                path = String(raw.drop(while: { $0 != ":" }).dropFirst(2))
                continue
            }
            if raw.hasPrefix("*** Move to: ") || raw.hasPrefix("@@") { continue }
            guard path != nil, let first = raw.first else { continue }
            let text = String(raw.dropFirst())
            switch first {
            case "+": newNumber += 1; lines.append(DiffLine(kind: .added, text: text, oldNumber: nil, newNumber: newNumber))
            case "-": oldNumber += 1; lines.append(DiffLine(kind: .removed, text: text, oldNumber: oldNumber, newNumber: nil))
            case " ": oldNumber += 1; newNumber += 1; lines.append(DiffLine(kind: .context, text: text, oldNumber: oldNumber, newNumber: newNumber))
            default: continue
            }
        }
        flush()
        return files
    }
}
