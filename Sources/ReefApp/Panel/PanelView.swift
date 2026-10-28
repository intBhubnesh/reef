import ReefCore
import SwiftUI

/// Expanded panel content: header row, then one card per session (pending requests first, oldest first).
struct PanelView: View {
    @Environment(AppState.self) private var app
    let maxHeight: CGFloat

    var body: some View {
        VStack(spacing: 10) {
            HeaderRow()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(app.pendingRequests, id: \.request.requestID) { entry in
                        card(for: entry.request, in: entry.session)
                    }
                    ForEach(app.visibleSessions.filter { $0.pending.isEmpty }, id: \.key) { session in
                        if app.revealedKeys.contains(session.key), session.status == .done || session.status == .failed {
                            CompletionCardView(session: session)
                        } else {
                            SessionCardView(session: session)
                        }
                    }
                    if app.visibleSessions.isEmpty {
                        Text("Start Claude Code or Codex in a terminal and it will show up here.")
                            .font(Theme.body).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: maxHeight - 60)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func card(for request: PendingRequest, in session: Session) -> some View {
        switch request.kind {
        case .permission: ApprovalCardView(session: session, request: request)
        case .question: QuestionCardView(session: session, request: request)
        case .plan: PlanCardView(session: session, request: request)
        }
    }
}
