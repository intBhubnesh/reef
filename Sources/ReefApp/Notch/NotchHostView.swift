import ReefCore
import SwiftUI

/// Root SwiftUI view of the notch window: morphs between the pill and the expanded panel.
struct NotchHostView: View {
    let controller: NotchWindowController
    @Environment(AppState.self) private var app

    var body: some View {
        let expanded = app.notch.state.isExpanded
        let geometry = controller.geometry
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(bottomRadius: expanded ? Theme.panelRadius : Theme.pillRadius)
                    .fill(Theme.panel)
                    .shadow(color: .black.opacity(expanded ? 0.45 : 0.25), radius: expanded ? 18 : 6, y: expanded ? 8 : 2)
                if expanded {
                    PanelView(maxHeight: geometry.panelRect.height)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    PillView()
                        .frame(height: geometry.pillRect.height)
                        .transition(.opacity)
                }
            }
            .frame(width: expanded ? geometry.panelRect.width : geometry.pillRect.width)
            .fixedSize(horizontal: false, vertical: true)
            .onTapGesture { if !expanded { app.click() } }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: expanded)
    }
}
