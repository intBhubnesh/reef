import ReefCore
import SwiftUI

/// Root view of the notch window.
///
/// The island's silhouette is a mask, not a layout. The pill and the panel are each laid out once
/// at their own final size, and the spring runs on the notch shape that masks them, so nothing
/// inside re-lays out while the island moves: animating the panel's own frame reflowed its scroll
/// view on every frame, which is what made the expansion feel soft and let rows overlap in
/// flight. Growth is anchored to the top centre, where the notch is. The window never animates:
/// it is sized to the target plus overshoot headroom before the spring starts.
struct NotchHostView: View {
    let controller: NotchWindowController
    @Environment(AppState.self) private var app
    @Namespace private var island
    @State private var hoveringPill = false
    /// The panel stays mounted until the collapse has settled, so its content shrinks away under
    /// the mask instead of vanishing the instant the island starts closing. Unmounting matters:
    /// a mounted panel keeps its sprites animating.
    @State private var panelMounted = false
    @State private var unmount: Task<Void, Never>?
    /// 0 is the pill, 1 the panel. The spring runs on this number and the mask reads it, because
    /// an implicit animation inside a mask never reaches the shape's frame.
    @State private var openness: Double = 0

    private var expanded: Bool { app.notch.state.isExpanded }

    var body: some View {
        let geometry = controller.geometry
        let reduce = app.reduceMotion
        let transition = app.notch.lastTransition
        let pill = geometry.pillRect.size
        let slack = Motion.overshootHeadroom

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if panelMounted {
                    // Final width and natural height from the first frame. The mask decides how
                    // much of it is visible (M3, M4: the header fades in place, the rows follow
                    // slightly later and drift down as they arrive). On the way out it does not
                    // fade at all: M5 and M7 show the content riding the shrinking frame.
                    PanelView(maxHeight: geometry.panelRect.height, namespace: island)
                        .frame(width: geometry.panelRect.width)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(panelShown ? 1 : 0)
                        .animation(transition.reveal(reduceMotion: reduce, row: false), value: panelShown)
                        .offset(y: panelShown ? 0 : -Motion.rowDrift)
                        .animation(transition.reveal(reduceMotion: reduce, row: true), value: panelShown)
                        .allowsHitTesting(expanded)
                }
                PillView(namespace: island, spriteIsSource: !expanded)
                    .frame(width: pill.width, height: pill.height)
                    .opacity(expanded ? 0 : 1)
                    .animation(pillFade(reduceMotion: reduce), value: expanded)
                    // Invisible is not untouchable: without this the pill would keep swallowing
                    // clicks meant for the panel header behind it.
                    .allowsHitTesting(!expanded)
                    .onHover { hoveringPill = $0 }
                    .onTapGesture { if !expanded { app.click() } }
            }
            // Room for the spring to overshoot into. A mask can only reveal pixels the view
            // actually draws, so without this the bounce would square off the bottom corners.
            .padding(.horizontal, slack)
            .padding(.bottom, slack)
            .background(Theme.panel.allowsHitTesting(false))
            .mask(alignment: .top) { silhouette(pill: pill, slack: slack) }
            .compositingGroup()
            .shadow(color: .black.opacity(expanded ? 0.45 : 0.25),
                    radius: expanded ? 18 : 6, y: expanded ? 8 : 2)
            .animation(transition.animation(reduceMotion: reduce), value: expanded)
            .scaleEffect(!expanded && hoveringPill && !reduce ? Motion.pillHoverScale : 1, anchor: .top)
            .animation(.easeOut(duration: Motion.pillHoverDuration), value: hoveringPill)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            panelMounted = expanded
            openness = expanded ? 1 : 0
        }
        .onChange(of: expanded) { _, isExpanded in
            mount(isExpanded)
            // Read the transition now, not from the body that set this closure up: that one was
            // rendered before the state changed and still carries the previous motion.
            let motion = app.notch.lastTransition.animation(reduceMotion: app.reduceMotion)
            withAnimation(motion) { openness = isExpanded ? 1 : 0 }
        }
    }

    /// The panel's content is hidden only before it has been revealed. Once the island starts
    /// closing it stays on screen and the shrinking mask takes it away.
    private var panelShown: Bool { app.contentRevealed || !expanded }

    /// The pill fades out as the island opens past it, and comes back only once the island is
    /// nearly closed: fading it in at the start of a collapse would float it over the panel.
    private func pillFade(reduceMotion: Bool) -> Animation {
        if reduceMotion { return .easeOut(duration: Motion.reducedFade) }
        // Out quickly, because for those few frames the pill's sprites sit on top of the header
        // text the island is revealing. Back in only once the island is nearly closed again.
        guard expanded else {
            return .easeOut(duration: Motion.headerFadeDuration).delay(Motion.collapseResponse / 2)
        }
        return .easeOut(duration: Motion.autoRevealFadeDuration)
    }

    /// The island outline at its animated size, centred on the notch and flush with the top.
    /// `openness` is already springing, so every frame of it is drawn here; a spring past 1 is
    /// the overshoot, which is what the slack around the content is for.
    private func silhouette(pill: CGSize, slack: CGFloat) -> some View {
        GeometryReader { proxy in
            // What is drawn, less the overshoot room, is the island at rest. Content that grows
            // while the panel is open changes this immediately, which is the snap it should get.
            let rest = CGSize(width: max(proxy.size.width - slack * 2, pill.width),
                              height: max(proxy.size.height - slack, pill.height))
            IslandMask(openness: openness, pill: pill, rest: rest, topRadius: Metrics.topFlare)
                .fill(.white)
        }
    }

    private func mount(_ isExpanded: Bool) {
        unmount?.cancel()
        guard !isExpanded else { panelMounted = true; return }
        unmount = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((Motion.collapseResponse + Motion.windowShrinkExtra) * 1_000_000_000))
            guard !Task.isCancelled, !expanded else { return }
            panelMounted = false
        }
    }
}
