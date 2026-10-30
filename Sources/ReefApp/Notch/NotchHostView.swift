import ReefCore
import SwiftUI

/// Root view of the notch window. The window itself is never animated: it is sized to the
/// target plus overshoot headroom first, and the spring runs on the shape drawn inside it,
/// so the bounce is never clipped.
struct NotchHostView: View {
    let controller: NotchWindowController
    @Environment(AppState.self) private var app
    @Namespace private var island
    @State private var hoveringPill = false

    private var expanded: Bool { app.notch.state.isExpanded }

    var body: some View {
        let geometry = controller.geometry
        let reduce = app.reduceMotion
        let transition = app.notch.lastTransition
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(bottomRadius: expanded ? Metrics.panelBottomRadius : Metrics.pillBottomRadius,
                           topRadius: Metrics.topFlare)
                    .fill(Theme.panel)
                    .shadow(color: .black.opacity(expanded ? 0.45 : 0.25),
                            radius: expanded ? 18 : 6, y: expanded ? 8 : 2)
                if expanded {
                    // Header and rows reveal on their own beats (M3, M4): the header fades in
                    // place, the rows follow slightly later and drift down as they arrive.
                    PanelView(maxHeight: geometry.panelRect.height, namespace: island)
                        .opacity(app.contentRevealed ? 1 : 0)
                        .animation(transition.reveal(reduceMotion: reduce, row: false), value: app.contentRevealed)
                        .offset(y: app.contentRevealed ? 0 : -Motion.rowDrift)
                        .animation(transition.reveal(reduceMotion: reduce, row: true), value: app.contentRevealed)
                } else {
                    PillView(namespace: island)
                        .frame(height: geometry.pillRect.height)
                }
            }
            .frame(width: expanded ? geometry.panelRect.width : geometry.pillRect.width)
            .fixedSize(horizontal: false, vertical: true)
            .scaleEffect(!expanded && hoveringPill && !reduce ? Motion.pillHoverScale : 1, anchor: .top)
            .animation(.easeOut(duration: Motion.pillHoverDuration), value: hoveringPill)
            .onHover { hoveringPill = $0 }
            .onTapGesture { if !expanded { app.click() } }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(transition.animation(reduceMotion: reduce), value: expanded)
    }
}
