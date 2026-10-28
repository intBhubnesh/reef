import AppKit
import SwiftUI

struct AboutTab: View {
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return b.map { "\(v) (\($0))" } ?? v
    }

    var body: some View {
        SettingsGroup(title: "Reef") {
            SettingsRow(title: "Version") { Text(version).foregroundStyle(.secondary) }
            SettingsRow(title: "Source") {
                Link("github.com/bhubnesh/reef", destination: URL(string: "https://github.com/bhubnesh/reef")!)
            }
            SettingsRow(title: "Log file", subtitle: Paths.logFile.path) {
                Button("Export log") { NSWorkspace.shared.activateFileViewerSelecting([Paths.logFile]) }
            }
        }
        SettingsGroup(title: "Acknowledgements") {
            SettingsRow(title: "Vibe Island", subtitle: "The app whose interaction model Reef follows. No code or assets were reused.") { EmptyView() }
            SettingsRow(title: "Departure Mono", subtitle: "SIL Open Font License, when bundled via scripts/fetch-fonts.sh.") { EmptyView() }
        }
        HStack {
            Spacer()
            Button("Quit Reef") { NSApp.terminate(nil) }.tint(.red)
        }
    }
}
