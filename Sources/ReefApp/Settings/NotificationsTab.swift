import ReefCore
import SwiftUI

struct NotificationsTab: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        SettingsGroup(title: "Sounds") {
            SettingsRow(title: "Mute all sounds") {
                Toggle("", isOn: $app.settings.muted).labelsHidden().toggleStyle(.switch)
            }
            SettingsRow(title: "Work started", subtitle: "An agent begins a new turn.") {
                HStack {
                    Button("Play") { app.sounds.play(.started) }.disabled(app.settings.muted)
                    Toggle("", isOn: $app.settings.soundStarted).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsRow(title: "Action completed", subtitle: "A tool or agent action finishes.") {
                HStack {
                    Button("Play") { app.sounds.play(.actionCompleted) }.disabled(app.settings.muted)
                    Toggle("", isOn: $app.settings.soundActionCompleted).labelsHidden().toggleStyle(.switch)
                }
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
        SettingsGroup(title: "iPhone notifications · Bark") {
            SettingsRow(title: "Enable Bark",
                        subtitle: "Send agent alerts to the Bark app on your iPhone.") {
                Toggle("", isOn: $app.settings.barkEnabled).labelsHidden().toggleStyle(.switch)
            }
            SettingsRow(title: "Server", subtitle: "Use api.day.app or your self-hosted bark-server.") {
                TextField("https://api.day.app", text: $app.settings.barkServerURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
            }
            SettingsRow(title: "Device key or test URL", subtitle: "Paste either from Bark; stored only in this Mac’s Keychain.") {
                SecureField("From the Bark app", text: $app.barkDeviceKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
            }
            SettingsRow(title: "Notify for") {
                HStack(spacing: 12) {
                    Toggle("Input", isOn: $app.settings.barkNotifyInputNeeded)
                    Toggle("Done", isOn: $app.settings.barkNotifyDone)
                    Toggle("Failed", isOn: $app.settings.barkNotifyFailed)
                }
                .toggleStyle(.checkbox)
                .disabled(!app.settings.barkEnabled)
            }
            SettingsRow(title: "Delivery level") {
                Picker("", selection: $app.settings.barkLevel) {
                    Text("Active").tag(BarkNotificationLevel.active.rawValue)
                    Text("Time sensitive").tag(BarkNotificationLevel.timeSensitive.rawValue)
                    Text("Passive").tag(BarkNotificationLevel.passive.rawValue)
                }
                .labelsHidden()
                .frame(width: 150)
            }
            SettingsRow(title: "Sound", subtitle: "Optional Bark sound name; blank uses the app default.") {
                TextField("Default", text: $app.settings.barkSound)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
            }
            SettingsRow(title: "Connection") {
                HStack(spacing: 10) {
                    if let status = app.barkStatus {
                        Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Link("Bark setup", destination: URL(string: "https://bark.day.app/#/en-us/")!)
                    Button(app.barkTestInProgress ? "Sending…" : "Send test") { app.testBark() }
                        .disabled(!app.barkIsConfigured || app.barkTestInProgress)
                }
            }
        }
    }
}
