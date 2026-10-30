import ReefCore
import SwiftUI

/// Colours read off the reference screenshots (`LAYOUT-SPEC.md` §9). Sizes live in `Metrics`.
enum Theme {
    // Surfaces
    static let panel = Color.black
    static let completionCard = Color(hex: 0x111111)
    static let subagentBox = Color(hex: 0x141414)
    static let card = Color(hex: 0x1A1A1A)
    static let bannerBackground = Color(hex: 0x1A120C)
    static let bannerBorder = Color(hex: 0x3A2A1C)
    static let bannerIcon = Color(hex: 0x3B2414)
    static let headerHighlight = Color(hex: 0x1C1C1E)
    static let cardBorder = Color(hex: 0x2A2A2A)
    static let chip = Color(hex: 0x2C2C2E)
    static let divider = Color(hex: 0x3A3A3C)
    static let inset = Color.black.opacity(0.35)

    // Text
    static let textPrimary = Color(hex: 0xF2F2F2)
    static let textBody = Color(hex: 0xE5E5EA)
    static let textChip = Color(hex: 0xB0B0B5)
    static let textSecondary = Color(hex: 0x9A9A9E)
    static let textTertiary = Color(hex: 0x8E8E93)

    // Accents
    static let done = Color(hex: 0x30D158)
    static let waiting = Color(hex: 0xF59E3A)
    static let accent = Color(hex: 0x4A8CFF)
    static let failed = Color(hex: 0xFF5B5B)
    static let claudeChip = Color(hex: 0x3A2A22)
    static let claudeChipText = Color(hex: 0xD9876A)
    static let codexChip = Color(hex: 0x1F3A5A)
    static let codexChipText = Color(hex: 0x6FA8FF)

    // Type
    static let body = Font.system(size: 13)
    static let bodyEmphasis = Font.system(size: 14, weight: .semibold)
    static let small = Font.system(size: 11)
    static let caption = Font.system(size: 12)
    static let mono = Font.system(size: 12, design: .monospaced)
    static let headerMono = Font.system(size: 13, weight: .bold, design: .monospaced)

    /// One glance tells you what an agent needs: working, waiting on you, done, failed.
    static func statusColor(_ status: SessionStatus) -> Color {
        switch status {
        case .idle, .working, .runningTool, .compacting: return accent
        case .waitingForApproval, .waitingForQuestion, .waitingForPlan: return waiting
        case .done: return done
        case .failed: return failed
        }
    }

    static func chipColors(_ source: AgentSource) -> (background: Color, text: Color) {
        source == .claude ? (claudeChip, claudeChipText) : (codexChip, codexChipText)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
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

    /// Full Markdown, so plan and completion cards show headings and bullets as formatting
    /// rather than literal characters.
    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .full,
                                                              failurePolicy: .returnPartiallyParsedIfPossible)))
            ?? AttributedString(text)
    }
}
