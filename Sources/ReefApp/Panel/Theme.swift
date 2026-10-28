import SwiftUI

enum Theme {
    static let panel = Color.black
    static let card = Color(red: 0.08, green: 0.08, blue: 0.08)
    static let cardBorder = Color(red: 0.12, green: 0.12, blue: 0.12)
    static let chip = Color(red: 0.16, green: 0.16, blue: 0.16)
    static let textPrimary = Color(red: 0.95, green: 0.95, blue: 0.95)
    static let textSecondary = Color(red: 0.6, green: 0.6, blue: 0.6)
    static let accent = Color(red: 0.43, green: 0.63, blue: 1.0)
    static let waiting = Color(red: 1.0, green: 0.7, blue: 0.25)
    static let done = Color(red: 0.3, green: 0.85, blue: 0.39)
    static let failed = Color(red: 1.0, green: 0.36, blue: 0.36)
    static let panelRadius: CGFloat = 24
    static let pillRadius: CGFloat = 16
    static let cardRadius: CGFloat = 12
    static let body = Font.system(size: 13)
    static let small = Font.system(size: 11)
    static let mono = Font.system(size: 12, design: .monospaced)
}

enum Format {
    static func elapsed(since date: Date, now: Date = Date()) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        let h = m / 60
        return m % 60 == 0 ? "\(h)h" : "\(h)h\(m % 60)m"
    }

    static func firstLine(_ text: String?, limit: Int = 60) -> String {
        guard let text else { return "" }
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
    }

    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
