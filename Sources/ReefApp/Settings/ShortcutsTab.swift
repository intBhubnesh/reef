import SwiftUI

struct ShortcutsTab: View {
    private let rows: [(String, String)] = [
        ("⌃Y", "Allow the oldest pending request, or approve a plan"),
        ("⌃N", "Deny the oldest pending request"),
        ("⌃A", "Always allow (Claude Code, session scope)"),
        ("⌃T", "Jump to the terminal of the oldest pending request"),
        ("⌃↩", "Submit the selected answers to a question"),
        ("esc", "Collapse the panel"),
    ]

    var body: some View {
        SettingsGroup(title: "While the panel is expanded") {
            ForEach(rows, id: \.0) { row in
                SettingsRow(title: row.1) {
                    Text(row.0)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        Text("Customisable shortcuts are planned for a later version.").font(.caption).foregroundStyle(.secondary)
    }
}
