import ReefCore
import SwiftUI

struct DisplayTab: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        SettingsGroup(title: "Preview") {
            HStack {
                Spacer()
                PillPreview()
                Spacer()
            }
            .padding(.vertical, 16)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        SettingsGroup(title: "Panel size") {
            SettingsRow(title: "Max panel width", subtitle: "\(Int(app.settings.panelMaxWidth)) pt") {
                Slider(value: $app.settings.panelMaxWidth, in: 400...900, step: 8).frame(width: 220)
            }
            SettingsRow(title: "Max panel height", subtitle: "\(Int(app.settings.panelMaxHeight)) pt") {
                Slider(value: $app.settings.panelMaxHeight, in: 300...900, step: 10).frame(width: 220)
            }
        }
        SettingsGroup(title: "Session card") {
            SettingsRow(title: "Show project name") {
                Toggle("", isOn: $app.settings.showProject).labelsHidden().toggleStyle(.switch)
            }
            SettingsRow(title: "Show git branch") {
                Toggle("", isOn: $app.settings.showBranch).labelsHidden().toggleStyle(.switch)
            }
            SettingsRow(title: "Show subagents", subtitle: "List child agents under their session.") {
                Toggle("", isOn: $app.settings.showSubagents).labelsHidden().toggleStyle(.switch)
            }
        }
    }
}

/// A static pill with two example sessions, for the Display tab.
struct PillPreview: View {
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                SpriteView(source: .claude, status: .working)
                SpriteView(source: .codex, status: .waitingForApproval)
            }
            .padding(.leading, 12)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Circle().fill(Theme.waiting).frame(width: 6, height: 6)
                Text("2").font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
            }
            .padding(.trailing, 12)
        }
        .frame(width: 249, height: 33)
        .background(NotchShape(bottomRadius: Metrics.pillBottomRadius).fill(Theme.panel))
    }
}
