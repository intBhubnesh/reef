import SwiftUI

struct GeneralTab: View {
    @Environment(AppState.self) private var app
    @State private var loginError: String?

    var body: some View {
        @Bindable var app = app
        SettingsGroup(title: "System") {
            SettingsRow(title: "Launch at Login", subtitle: loginError) {
                Toggle("", isOn: Binding(
                    get: { app.settings.launchAtLogin },
                    set: { on in
                        loginError = LaunchAtLogin.set(on)
                        app.settings.launchAtLogin = on && loginError == nil
                    }
                )).labelsHidden().toggleStyle(.switch)
            }
        }
        SettingsGroup(title: "Expansion") {
            SettingsRow(title: "Expand notch on hover") {
                Toggle("", isOn: $app.settings.hoverExpand).labelsHidden().toggleStyle(.switch)
            }
            SettingsRow(title: "Hover duration", subtitle: String(format: "%.2fs", app.settings.hoverDelay)) {
                Slider(value: $app.settings.hoverDelay, in: 0.05...1.0, step: 0.05).frame(width: 220)
            }
            SettingsRow(title: "Auto-collapse on mouse leave") {
                Toggle("", isOn: $app.settings.autoCollapseOnLeave).labelsHidden().toggleStyle(.switch)
            }
            SettingsRow(title: "Auto reveal dwell", subtitle: "How long completion cards stay open. Press esc to close sooner.") {
                Stepper("\(Int(app.settings.revealDwell))s", value: $app.settings.revealDwell, in: 1...15, step: 1)
            }
        }
        SettingsGroup(title: "Sessions") {
            SettingsRow(title: "Idle session cleanup", subtitle: "Remove sessions with no events for this long.") {
                Stepper("\(Int(app.settings.idleCleanupHours))h", value: $app.settings.idleCleanupHours, in: 1...24, step: 1)
            }
            SettingsRow(title: "Show headless sessions", subtitle: "Runs with no terminal, such as claude -p. They never get a jump button.") {
                Toggle("", isOn: $app.settings.showHeadless).labelsHidden().toggleStyle(.switch)
            }
        }
    }
}
