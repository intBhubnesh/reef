import ReefCore
import SwiftUI

/// The collapsed island: one character per visible session on the left, the count and an
/// attention dot on the right. Both groups carry matched-geometry ids so they travel to their
/// panel positions during an expansion rather than cross-fading (M5).
struct PillView: View {
    @Environment(AppState.self) private var app
    let namespace: Namespace.ID

    var body: some View {
        let sessions = app.visibleSessions
        HStack(spacing: 0) {
            HStack(spacing: Metrics.pillSpriteGap) {
                ForEach(sessions, id: \.key) { session in
                    SessionSprite(session: session, cell: Metrics.pillSpriteSize / CGFloat(Metrics.spriteColumns))
                        .matchedGeometryEffect(id: session.key, in: namespace)
                }
            }
            .padding(.leading, Metrics.pillSideInset)
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
                .padding(.trailing, Metrics.pillSideInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

extension View {
    /// Applies a matched-geometry id when a namespace is available, so the same card view can
    /// be used inside and outside the morphing island.
    @ViewBuilder
    func matchedGeometry(id: some Hashable, in namespace: Namespace.ID?) -> some View {
        if let namespace { matchedGeometryEffect(id: id, in: namespace) } else { self }
    }
}
