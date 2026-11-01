import ReefCore
import SwiftUI

/// Shown after a turn ends: Done (or Failed), elapsed time, the last assistant message.
struct CompletionCardView: View {
    @Environment(AppState.self) private var app
    let session: Session
    @State private var expanded = false
    @State private var contentHeight: CGFloat = 0

    private var failed: Bool { session.status == .failed }
    private var collapsedHeight: CGFloat { Metrics.textLeading * 3 }
    private var hasOverflow: Bool { contentHeight > collapsedHeight + 1 }
    private var visibleContentHeight: CGFloat {
        guard contentHeight > 0 else { return collapsedHeight }
        return expanded ? contentHeight : min(contentHeight, collapsedHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { app.jump(session: session) } label: {
                HStack(spacing: 8) {
                    Image(systemName: failed ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(failed ? Theme.failed : Theme.done)
                        .font(.system(size: 16, weight: .semibold))
                    Text(failed ? "Failed" : "Done")
                        .font(Theme.body.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text(session.project ?? "").font(Theme.body).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    Spacer()
                    AgentIconChip(source: session.key.source)
                    Chip(text: Format.elapsed(since: session.startedAt))
                }
            }
            .buttonStyle(.plain)
            .help("Jump to agent")

            if let message = session.lastAssistantMessage, !message.isEmpty {
                MarkdownText(text: message)
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: CompletionContentHeightKey.self,
                                                   value: proxy.size.height)
                        }
                    }
                    .frame(height: visibleContentHeight, alignment: .top)
                    .clipped()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onPreferenceChange(CompletionContentHeightKey.self) { measured in
                        guard measured > 0, abs(measured - contentHeight) > 0.5 else { return }
                        contentHeight = measured
                    }

                if hasOverflow {
                    Button {
                        withAnimation(.smooth(duration: Motion.disclosureResponse)) {
                            expanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(expanded ? "Less" : "More")
                                .contentTransition(.opacity)
                                .frame(width: 34, alignment: .leading)
                            Image(systemName: "chevron.down")
                                .rotationEffect(.degrees(expanded ? 180 : 0))
                        }
                    }
                    .buttonStyle(PanelButtonStyle(role: .quiet))
                    .accessibilityLabel(expanded ? "Collapse completion" : "Expand completion")
                }
            } else if failed {
                Text("The turn ended with an error.").font(Theme.body).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.completionCard, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
            .stroke((failed ? Theme.failed : Theme.done).opacity(0.4)))
        .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .contextMenu {
            Button("Dismiss agent", systemImage: "xmark.circle") { app.dismiss(session: session) }
        }
    }
}

private struct CompletionContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
