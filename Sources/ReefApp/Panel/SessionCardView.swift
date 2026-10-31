import ReefCore
import SwiftUI

struct SessionCardView: View {
    @Environment(AppState.self) private var app
    let session: Session
    var namespace: Namespace.ID?

    var body: some View {
        let watched = session.ingress == .transcript
        Button { app.jump(session: session) } label: {
            HStack(alignment: .top, spacing: 0) {
                // L4: the character is centred on the first two text lines, not the whole row,
                // so it stays beside the title when subagents push the card taller.
                SessionSprite(session: session, cell: Metrics.rowSpriteWidth / CGFloat(Metrics.spriteColumns))
                    .matchedGeometry(id: session.key, in: namespace)
                    // L4: one fixed-width gutter, so the text column lands at the measured
                    // inset on every row regardless of what the sprite draws.
                    .frame(width: Metrics.textColumn - Metrics.cardPadding,
                           height: Metrics.textLeading * 2, alignment: .leading)
                VStack(alignment: .leading, spacing: 0) {
                    Text(titleLine)
                        .font(Theme.bodyEmphasis)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .frame(height: Metrics.textLeading, alignment: .leading)
                    if let prompt = session.lastPrompt {
                        (Text("You: ").foregroundStyle(Theme.textChip) + Text(Format.firstLine(prompt, limit: 90)))
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .frame(height: Metrics.textLeading, alignment: .leading)
                    }
                    Text(statusLine)
                        .font(Theme.body)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .frame(height: Metrics.textLeading, alignment: .leading)
                    if !session.subagents.isEmpty, app.showSubagents {
                        SubagentListView(subagents: session.subagents)
                            .padding(.top, 6)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: Metrics.chipGap) {
                    let colors = Theme.chipColors(session.key.source)
                    Chip(text: AgentLabel.name(session.key.source), tint: colors.text, background: colors.background)
                    if let terminal = AgentLabel.terminalName(session.terminal) { Chip(text: terminal) }
                    Chip(text: Format.elapsed(since: session.startedAt))
                    // Read-only: this session came from a transcript, so there is no hook to
                    // answer and nothing to jump to.
                    if watched { Chip(text: "Watched") }
                    if session.status == .done {
                        Circle().fill(Theme.done).frame(width: Metrics.statusDotSize, height: Metrics.statusDotSize)
                    }
                }
                .padding(.trailing, Metrics.rightInset - Metrics.cardPadding)
            }
            .padding(Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).stroke(Theme.cardBorder))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(watched ? "Focus VS Code. Read from the Codex transcript, so approvals happen there." : "Jump to terminal")
    }

    private var titleLine: String {
        var parts: [String] = []
        if app.showProject, let project = session.project { parts.append(project) }
        if app.showBranch, let branch = session.branch { parts.append(branch) }
        let head = parts.joined(separator: " · ")
        let prompt = Format.firstLine(session.lastPrompt)
        if head.isEmpty { return prompt.isEmpty ? session.key.sessionID : prompt }
        return prompt.isEmpty ? head : "\(head) · \(prompt)"
    }

    private var statusLine: String {
        switch session.status {
        case .idle: return "Idle"
        case .working: return "Working…"
        case .runningTool(let tool): return "Running \(tool)" + (session.elapsedToolStart.map { " · \(Format.elapsed(since: $0))" } ?? "")
        case .waitingForApproval: return "Waiting for your approval"
        case .waitingForQuestion: return "Has a question for you"
        case .waitingForPlan: return "Plan ready for review"
        case .done: return "Done"
        case .failed: return "Failed"
        case .compacting: return "Compacting context…"
        }
    }
}

struct SubagentListView: View {
    let subagents: [Subagent]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Subagents (\(subagents.count))")
                .font(Theme.body.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            ForEach(subagents, id: \.id) { agent in
                HStack(spacing: 6) {
                    Circle().fill(agent.status == .done ? Theme.done : Theme.accent).frame(width: 5, height: 5)
                    Text(agent.description).font(Theme.body).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text(agent.status == .done ? "done" : "running · \(Format.elapsed(since: agent.startedAt))")
                        .font(Theme.small).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(Metrics.subagentBoxInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.subagentBox, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }
}
