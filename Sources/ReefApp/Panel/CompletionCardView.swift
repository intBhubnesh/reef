import ReefCore
import SwiftUI

/// Shown after a turn ends: Done (or Failed), elapsed time, the last assistant message.
struct CompletionCardView: View {
    @Environment(AppState.self) private var app
    let session: Session
    @State private var expanded = false

    private var failed: Bool { session.status == .failed }

    var body: some View {
        Button { app.jump(session: session) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: failed ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(failed ? Theme.failed : Theme.done)
                        .font(.system(size: 16, weight: .semibold))
                    Text(failed ? "Failed" : "Done")
                        .font(Theme.body.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text(session.project ?? "").font(Theme.body).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    Spacer()
                    Chip(text: AgentLabel.name(session.key.source))
                    Chip(text: Format.elapsed(since: session.startedAt))
                }
                if let message = session.lastAssistantMessage, !message.isEmpty {
                    MarkdownText(text: message)
                        .lineLimit(expanded ? nil : 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if message.count > 180 || message.filter(\.isNewline).count >= 3 {
                        Button(expanded ? "Less" : "More") { expanded.toggle() }
                            .buttonStyle(PanelButtonStyle(role: .quiet))
                    }
                } else if failed {
                    Text("The turn ended with an error.").font(Theme.body).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .stroke((failed ? Theme.failed : Theme.done).opacity(0.4)))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
