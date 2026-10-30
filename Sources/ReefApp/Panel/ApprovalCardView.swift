import ReefCore
import SwiftUI

/// A permission request: what the agent wants to do, and Allow / Deny / Always allow.
struct ApprovalCardView: View {
    @Environment(AppState.self) private var app
    let session: Session
    let request: PendingRequest

    private var presentation: ApprovalPresentation { app.presentation(for: request, in: session) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(session: session, badge: request.event.toolName ?? "tool", badgeTint: Theme.waiting,
                       subtitle: "wants permission")
            body(for: presentation)
            footer
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .stroke(request.isLive ? Theme.waiting.opacity(0.5) : Theme.cardBorder))
    }

    @ViewBuilder
    private func body(for presentation: ApprovalPresentation) -> some View {
        switch presentation {
        case let .bash(command, description):
            VStack(alignment: .leading, spacing: 6) {
                if let description, !description.isEmpty {
                    Text(description).font(Theme.body).foregroundStyle(Theme.textSecondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(command).font(Theme.mono).foregroundStyle(Theme.textPrimary).textSelection(.enabled)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        case let .diff(path, lines):
            DiffView(path: path, lines: lines)
        case let .multiDiff(files):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                    DiffView(path: file.path, lines: file.lines, kind: file.kind)
                }
            }
        case let .summary(title, detail):
            HStack(spacing: 8) {
                Text(title).font(Theme.body.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(detail).font(Theme.mono).foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.middle)
            }
        case let .json(_, pretty):
            JSONBlock(text: pretty)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if request.isLive {
            HStack(spacing: 8) {
                if session.key.source == .claude, request.kind == .permission {
                    Button("Always allow") { app.alwaysAllow(requestID: request.requestID) }
                        .buttonStyle(PanelButtonStyle(role: .quiet))
                        .help("⌃A")
                }
                Spacer()
                Button("Deny") { app.decide(requestID: request.requestID, decision: .deny(message: "Denied from Reef")) }
                    .buttonStyle(PanelButtonStyle(role: .secondary))
                    .help("⌃N")
                Button("Allow") { app.decide(requestID: request.requestID, decision: .allow()) }
                    .buttonStyle(PanelButtonStyle(role: .primary))
                    .help("⌃Y")
            }
        } else {
            HStack {
                Label("Waiting in terminal", systemImage: "terminal")
                    .font(Theme.small).foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("Jump") { app.jump(session: session) }
                    .buttonStyle(PanelButtonStyle(role: .secondary))
                    .help("⌃T")
            }
        }
    }
}

struct CardHeader: View {
    let session: Session
    let badge: String
    let badgeTint: Color
    let subtitle: String

    var body: some View {
        HStack(spacing: 8) {
            SpriteView(source: session.key.source, status: session.status, pixel: 3)
            Text(session.project ?? AgentLabel.name(session.key.source))
                .font(Theme.body.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
            Text(subtitle).font(Theme.body).foregroundStyle(Theme.textSecondary)
            Chip(text: badge, tint: badgeTint, background: badgeTint.opacity(0.15))
            Spacer()
            Chip(text: AgentLabel.name(session.key.source))
        }
    }
}

struct JSONBlock: View {
    let text: String
    @State private var expanded = false

    private var lines: [String] { text.components(separatedBy: "\n") }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(expanded ? text : lines.prefix(12).joined(separator: "\n"))
                .font(Theme.mono).foregroundStyle(Theme.textPrimary.opacity(0.85))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if lines.count > 12 {
                Button(expanded ? "Less" : "Show all \(lines.count) lines") { expanded.toggle() }
                    .buttonStyle(PanelButtonStyle(role: .quiet))
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
