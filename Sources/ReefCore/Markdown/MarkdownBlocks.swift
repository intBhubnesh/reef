import Foundation

/// One block of a Markdown document. Foundation's `AttributedString(markdown:)` parses inline
/// styling but renders block elements run together, which turns a plan into one long line, so
/// Reef splits blocks itself and applies inline styling per block.
public enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case bullet(text: String, indent: Int)
    case numbered(number: Int, text: String)
    case paragraph(String)
    case code(String)
}

public enum MarkdownBlocks {
    public static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String]?

        func flushParagraph() {
            let joined = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            paragraph = []
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if let current = code {
                    blocks.append(.code(current.joined(separator: "\n")))
                    code = nil
                } else {
                    flushParagraph()
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(rawLine)
                continue
            }
            if line.isEmpty {
                flushParagraph()
                continue
            }
            if let heading = heading(line) {
                flushParagraph()
                blocks.append(heading)
                continue
            }
            if let bullet = bullet(line, raw: rawLine) {
                flushParagraph()
                blocks.append(bullet)
                continue
            }
            if let numbered = numbered(line) {
                flushParagraph()
                blocks.append(numbered)
                continue
            }
            paragraph.append(line)
        }
        if let current = code { blocks.append(.code(current.joined(separator: "\n"))) }
        flushParagraph()
        return blocks
    }

    private static func heading(_ line: String) -> MarkdownBlock? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }.count
        guard hashes <= 6 else { return nil }
        let text = line.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return .heading(level: hashes, text: text)
    }

    private static func bullet(_ line: String, raw: String) -> MarkdownBlock? {
        guard let marker = ["- ", "* ", "• "].first(where: { line.hasPrefix($0) }) else { return nil }
        let leading = raw.prefix { $0 == " " || $0 == "\t" }.count
        return .bullet(text: String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces),
                       indent: min(leading / 2, 3))
    }

    private static func numbered(_ line: String) -> MarkdownBlock? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, let number = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return .numbered(number: number, text: String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces))
    }
}
