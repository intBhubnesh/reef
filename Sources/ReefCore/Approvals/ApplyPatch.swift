import Foundation

/// Parses Codex `apply_patch` text (`*** Begin Patch` … `*** End Patch`) into per-file diff lines.
public enum ApplyPatch {
    public enum Kind: Equatable { case update, add, delete }

    public struct File: Equatable {
        public let path: String
        public let kind: Kind
        public let lines: [DiffLine]

        public init(path: String, kind: Kind = .update, lines: [DiffLine]) {
            self.path = path; self.kind = kind; self.lines = lines
        }
    }

    public static func files(from patch: String) -> [File] {
        var files: [File] = []
        var path: String?
        var kind: Kind = .update
        var lines: [DiffLine] = []
        var oldNumber = 0, newNumber = 0

        func flush() {
            if let path { files.append(File(path: path, kind: kind, lines: lines)) }
            path = nil; kind = .update; lines = []; oldNumber = 0; newNumber = 0
        }

        for raw in patch.components(separatedBy: "\n") {
            if raw.hasPrefix("*** Begin Patch") || raw.hasPrefix("*** End Patch") { continue }
            let headers: [(String, Kind)] = [("*** Update File: ", .update), ("*** Add File: ", .add), ("*** Delete File: ", .delete)]
            if let header = headers.first(where: { raw.hasPrefix($0.0) }) {
                flush()
                path = String(raw.dropFirst(header.0.count))
                kind = header.1
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
