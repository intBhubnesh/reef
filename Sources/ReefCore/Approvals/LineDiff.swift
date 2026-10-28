import Foundation

public struct DiffLine: Equatable {
    public enum Kind: Equatable { case context, added, removed }
    public let kind: Kind
    public let text: String
    public let oldNumber: Int?
    public let newNumber: Int?

    public init(kind: Kind, text: String, oldNumber: Int?, newNumber: Int?) {
        self.kind = kind; self.text = text; self.oldNumber = oldNumber; self.newNumber = newNumber
    }
}

/// Line-based diff (LCS) with unchanged runs collapsed to `context` lines on each side of a change.
public enum LineDiff {
    public static func compute(old: String, new: String, context: Int = 3) -> [DiffLine] {
        let a = old.isEmpty ? [] : old.components(separatedBy: "\n")
        let b = new.isEmpty ? [] : new.components(separatedBy: "\n")
        let full = fullDiff(a, b)
        guard full.contains(where: { $0.kind != .context }) else { return [] }
        return collapse(full, context: context)
    }

    private static func fullDiff(_ a: [String], _ b: [String]) -> [DiffLine] {
        let n = a.count, m = b.count
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var out: [DiffLine] = []
        var i = 0, j = 0
        while i < n, j < m {
            if a[i] == b[j] {
                out.append(DiffLine(kind: .context, text: a[i], oldNumber: i + 1, newNumber: j + 1)); i += 1; j += 1
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                out.append(DiffLine(kind: .removed, text: a[i], oldNumber: i + 1, newNumber: nil)); i += 1
            } else {
                out.append(DiffLine(kind: .added, text: b[j], oldNumber: nil, newNumber: j + 1)); j += 1
            }
        }
        while i < n { out.append(DiffLine(kind: .removed, text: a[i], oldNumber: i + 1, newNumber: nil)); i += 1 }
        while j < m { out.append(DiffLine(kind: .added, text: b[j], oldNumber: nil, newNumber: j + 1)); j += 1 }
        return out
    }

    private static func collapse(_ lines: [DiffLine], context: Int) -> [DiffLine] {
        var keep = Array(repeating: false, count: lines.count)
        for (index, line) in lines.enumerated() where line.kind != .context {
            for k in max(0, index - context)...min(lines.count - 1, index + context) { keep[k] = true }
        }
        return lines.enumerated().filter { keep[$0.offset] }.map(\.element)
    }
}
