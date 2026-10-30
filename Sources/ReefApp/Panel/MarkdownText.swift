import ReefCore
import SwiftUI

/// Renders Markdown with its block structure intact: headings, lists and paragraphs each get
/// their own line and styling, with inline emphasis and code applied per block.
struct MarkdownText: View {
    let text: String
    var baseFont: Font = Theme.body
    var color: Color = Theme.textBody

    private var blocks: [MarkdownBlock] { MarkdownBlocks.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                row(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(inline(text))
                .font(.system(size: level <= 1 ? 15 : 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 2)
        case let .bullet(text, indent):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(Theme.textTertiary)
                Text(inline(text)).font(baseFont).foregroundStyle(color)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(indent) * 12)
        case let .numbered(number, text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(number).").foregroundStyle(Theme.textTertiary).font(baseFont.monospacedDigit())
                Text(inline(text)).font(baseFont).foregroundStyle(color)
                Spacer(minLength: 0)
            }
        case let .paragraph(text):
            Text(inline(text))
                .font(baseFont)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .code(code):
            Text(code)
                .font(Theme.mono)
                .foregroundStyle(Theme.textPrimary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.inset, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    /// Inline styling only: bold, italics and `code` inside one block.
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                              failurePolicy: .returnPartiallyParsedIfPossible)))
            ?? AttributedString(text)
    }
}
