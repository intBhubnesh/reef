import ReefCore
import SwiftUI

struct SessionCardView: View {
    @Environment(AppState.self) private var app
    let session: Session
    var namespace: Namespace.ID?

    var body: some View {
        Button { app.jump(session: session) } label: {
            HStack(alignment: .top, spacing: 12) {
                SessionSprite(session: session, cell: Metrics.rowSpriteWidth / CGFloat(Metrics.spriteColumns))
                    .matchedGeometry(id: session.key, in: namespace)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(titleLine)
                        .font(Theme.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let prompt = session.lastPrompt {
                        (Text("You: ").foregroundStyle(Theme.textSecondary) + Text(Format.firstLine(prompt, limit: 90)))
                            .font(Theme.body)
                            .foregroundStyle(Theme.textPrimary.opacity(0.85))
                            .lineLimit(1)
                    }
                    Text(statusLine)
                        .font(Theme.small)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    if !session.subagents.isEmpty, app.showSubagents {
                        SubagentListView(subagents: session.subagents)
                            .padding(.top, 4)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Chip(text: AgentLabel.name(session.key.source), tint: session.key.source == .claude ? Theme.waiting : Theme.textPrimary)
                    if let terminal = AgentLabel.terminalName(session.terminal) { Chip(text: terminal) }
                    Chip(text: Format.elapsed(since: session.startedAt))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).stroke(Theme.cardBorder))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Jump to terminal")
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
                .font(Theme.small.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            ForEach(subagents, id: \.id) { agent in
                HStack(spacing: 6) {
                    Circle().fill(agent.status == .done ? Theme.done : Theme.accent).frame(width: 5, height: 5)
                    Text(agent.description).font(Theme.small).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text(agent.status == .done ? "done" : "running · \(Format.elapsed(since: agent.startedAt))")
                        .font(Theme.small).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
