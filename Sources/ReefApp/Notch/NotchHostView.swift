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
        let progress = min(max(openness, 0), 1)
        let panelProgress = panelRevealProgress(progress, transition: transition)
        let pillProgress = 1 - smoothstep(progress, from: 0.06, to: 0.28)

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
                        .opacity(panelShown ? panelProgress : 0)
                        .offset(y: panelShown ? -Motion.rowDrift * (1 - panelProgress) : -Motion.rowDrift)
                        .allowsHitTesting(expanded)
                }
                PillView(namespace: island, spriteIsSource: !expanded)
                    .frame(width: pill.width, height: pill.height)
                    .opacity(pillProgress)
                    // Invisible is not untouchable: without this the pill would keep swallowing
                    // clicks meant for the panel header behind it.
                    .allowsHitTesting(!expanded)
                    .onHover { hoveringPill = $0 }
                    .onTapGesture { if !expanded { app.click() } }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: IslandContentSizeKey.self, value: proxy.size)
                }
            }
            .onPreferenceChange(IslandContentSizeKey.self) { size in
                if expanded { controller.updateRenderedPanelSize(size) }
            }
            // Room for the spring to overshoot into. A mask can only reveal pixels the view
            // actually draws, so without this the bounce would square off the bottom corners.
            .padding(.horizontal, slack)
            .padding(.bottom, slack)
            .background(Theme.panel.allowsHitTesting(false))
            .mask(alignment: .top) { silhouette(pill: pill, slack: slack) }
            .compositingGroup()
            .shadow(color: .black.opacity(0.25 + 0.20 * progress),
                    radius: 6 + 12 * progress, y: 2 + 6 * progress)
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

    /// All visual layers read the same animated openness. This keeps the mask, content, pill and
    /// shadow on one native animation timeline instead of starting several implicit animations.
    private func panelRevealProgress(_ progress: Double, transition: NotchTransition) -> Double {
        guard expanded else { return 1 }
        let start = transition == .hoverExpand ? 0.20 : 0.08
        let end = transition == .hoverExpand ? 0.58 : 0.34
        return smoothstep(progress, from: start, to: end)
    }

    private func smoothstep(_ value: Double, from start: Double, to end: Double) -> Double {
        guard end > start else { return value >= end ? 1 : 0 }
        let unit = min(max((value - start) / (end - start), 0), 1)
        return unit * unit * (3 - 2 * unit)
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

private struct IslandContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
