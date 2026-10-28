import ReefCore
import SwiftUI

/// An `ExitPlanMode` card: read the plan, approve it or send feedback back.
struct PlanCardView: View {
    @Environment(AppState.self) private var app
    let session: Session
    let request: PendingRequest
    @State private var showFeedback = false
    @State private var feedback = ""

    private var plan: String { request.event.toolInput?["plan"] as? String ?? "(empty plan)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(session: session, badge: "Plan", badgeTint: Theme.accent, subtitle: "wants to leave plan mode")
            ScrollView {
                Text(Format.markdown(plan))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 240)
            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            if request.isLive {
                if showFeedback {
                    TextField("What should change?", text: $feedback, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(Theme.body)
                        .lineLimit(1...4)
                        .padding(8)
                        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                HStack(spacing: 8) {
                    Spacer()
                    if showFeedback {
                        Button("Cancel") { showFeedback = false }.buttonStyle(PanelButtonStyle(role: .quiet))
                        Button("Send feedback") { app.answerPlan(requestID: request.requestID, approve: false, feedback: feedback) }
                            .buttonStyle(PanelButtonStyle(role: .secondary))
                            .disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Button("Deny with feedback") { showFeedback = true }.buttonStyle(PanelButtonStyle(role: .secondary)).help("⌃N")
                        Button("Approve") { app.answerPlan(requestID: request.requestID, approve: true, feedback: "") }
                            .buttonStyle(PanelButtonStyle(role: .primary)).help("⌃Y")
                    }
                }
            } else {
                HStack {
                    Label("Waiting in terminal", systemImage: "terminal").font(Theme.small).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button("Jump") { app.jump(session: session) }.buttonStyle(PanelButtonStyle(role: .secondary))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.accent.opacity(request.isLive ? 0.5 : 0)))
    }
}
