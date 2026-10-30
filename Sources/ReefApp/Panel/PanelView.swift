import ReefCore
import SwiftUI

/// Expanded panel content: header band, an optional notice banner, then one card per session
/// with pending requests first, oldest first. Rhythm from LAYOUT-SPEC §1.
struct PanelView: View {
    @Environment(AppState.self) private var app
    let maxHeight: CGFloat
    let namespace: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            HeaderRow(namespace: namespace)
                .frame(height: Metrics.headerHeight)
                .padding(.horizontal, Metrics.cardPadding)

            ScrollView(showsIndicators: false) {
                VStack(spacing: Metrics.blockGap) {
                    if let notice = app.notice {
                        BannerCard(icon: "exclamationmark.triangle.fill",
                                   title: "Reef repaired your hooks",
                                   message: notice,
                                   dismiss: { app.notice = nil })
                    }
                    ForEach(app.pendingRequests, id: \.request.requestID) { entry in
                        card(for: entry.request, in: entry.session)
                    }
                    ForEach(app.visibleSessions.filter { $0.pending.isEmpty }, id: \.key) { session in
                        if app.revealedKeys.contains(session.key), session.status == .done || session.status == .failed {
                            CompletionCardView(session: session)
                        } else {
                            SessionCardView(session: session, namespace: namespace)
                        }
                    }
                    if app.visibleSessions.isEmpty, app.notice == nil {
                        Text("Start Claude Code or Codex in a terminal and it will show up here.")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    }
                }
                .frame(width: Metrics.contentWidth)
                .padding(.bottom, Metrics.bottomInset)
            }
            // No fixedSize: that would make the scroll view adopt its content's full height and
            // clip instead of scrolling once several sessions are open.
            .frame(maxHeight: maxHeight - Metrics.headerHeight - Metrics.bottomInset)
        }
        .frame(maxWidth: .infinity, alignment: .top)
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
