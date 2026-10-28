import SwiftUI

struct NotificationsTab: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        SettingsGroup(title: "Sounds") {
            SettingsRow(title: "Mute all sounds") {
                Toggle("", isOn: $app.settings.muted).labelsHidden().toggleStyle(.switch)
            }
            SettingsRow(title: "Input needed", subtitle: "An agent asks for permission or a question.") {
                HStack {
                    Button("Play") { app.sounds.play(.inputNeeded) }.disabled(app.settings.muted)
                    Toggle("", isOn: $app.settings.soundInputNeeded).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsRow(title: "Done", subtitle: "An agent finished its turn.") {
                HStack {
                    Button("Play") { app.sounds.play(.done) }.disabled(app.settings.muted)
                    Toggle("", isOn: $app.settings.soundDone).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsRow(title: "Failed", subtitle: "A turn ended with an error.") {
                HStack {
                    Button("Play") { app.sounds.play(.failed) }.disabled(app.settings.muted)
                    Toggle("", isOn: $app.settings.soundFailed).labelsHidden().toggleStyle(.switch)
                }
            }
        }
        SettingsGroup(title: "System notifications") {
            SettingsRow(title: "Notify when all agents finished",
                        subtitle: LaunchAtLogin.isAvailable ? "Posts a macOS notification when no agent is working anymore." : "Needs the Reef.app bundle.") {
                Toggle("", isOn: $app.settings.notifyAllFinished).labelsHidden().toggleStyle(.switch)
                    .disabled(!LaunchAtLogin.isAvailable)
            }
        }
    }
}
