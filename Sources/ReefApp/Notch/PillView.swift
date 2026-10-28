import ReefCore
import SwiftUI

/// The collapsed island: one sprite per visible session on the left, the count and an attention dot on the right.
struct PillView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let sessions = app.visibleSessions
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(sessions, id: \.key) { session in
                    SpriteView(source: session.key.source, status: session.status)
                }
            }
            .padding(.leading, 12)
            Spacer(minLength: 8)
            if !sessions.isEmpty {
                HStack(spacing: 6) {
                    if app.livePendingCount > 0 || sessions.contains(where: { $0.status.isWaitingOnUser }) {
                        Circle().fill(Theme.waiting).frame(width: 6, height: 6)
                    }
                    Text("\(sessions.count)")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
                .padding(.trailing, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}
