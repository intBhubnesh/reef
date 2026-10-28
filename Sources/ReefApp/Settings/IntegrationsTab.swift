import ReefCore
import SwiftUI

struct IntegrationsTab: View {
    @Environment(AppState.self) private var app
    @State private var refresh = 0
    @State private var error: String?

    var body: some View {
        SettingsGroup(title: "Agents") {
            agentRow(.claude, name: "Claude Code", file: "~/.claude/settings.json")
            agentRow(.codex, name: "Codex", file: "~/.codex/hooks.json")
        }
        if let error {
            Text(error).font(.caption).foregroundStyle(.red)
        }
        SettingsGroup(title: "Claude Code terminal titles") {
            SettingsRow(title: "CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1",
                        subtitle: "Reef sets this so tab titles can carry the session marker used to jump to Ghostty tabs.") {
                if HookInstaller.terminalTitleEnvSet {
                    Button("Undo") { HookInstaller.removeTerminalTitleEnv(); refresh += 1 }
                } else {
                    Text("Not set").foregroundStyle(.secondary)
                }
            }
        }
        SettingsGroup(title: "Permissions") {
            SettingsRow(title: "Accessibility", subtitle: "Needed to focus the right Ghostty tab. Re-grant after rebuilding an ad hoc signed app.") {
                if GhosttyAX.isTrusted {
                    Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("Open System Settings") {
                        GhosttyAX.requestAccess()
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .id(refresh)
    }

    @ViewBuilder
    private func agentRow(_ source: AgentSource, name: String, file: String) -> some View {
        let status = HookInstaller.status(source)
        SettingsRow(title: name, subtitle: subtitle(for: source, status: status, file: file)) {
            HStack(spacing: 8) {
                statusChip(status)
                if status.installedEvents.isEmpty {
                    Button("Install") { error = app.installHooks(source); refresh += 1 }
                } else {
                    if !status.isComplete { Button("Repair") { error = app.installHooks(source); refresh += 1 } }
                    Button("Uninstall") { error = app.uninstallHooks(source); refresh += 1 }
                }
            }
        }
        .id("\(source.rawValue)-\(refresh)")
    }

    private func subtitle(for source: AgentSource, status: HookConfig.HookStatus, file: String) -> String {
        var parts = [file]
        if source == .codex, !status.installedEvents.isEmpty {
            switch HookInstaller.codexTrusted() {
            case .some(true): parts.append("Hooks trusted by Codex.")
            case .some(false): parts.append("Run /hooks in Codex and trust the Reef entries.")
            case .none: parts.append("Trust unknown: run /hooks in Codex and trust the Reef entries.")
            }
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func statusChip(_ status: HookConfig.HookStatus) -> some View {
        if status.installedEvents.isEmpty {
            Text("Not installed").font(.caption).foregroundStyle(.secondary)
        } else if status.isComplete {
            Label("Installed", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        } else {
            Label("Missing \(status.missingEvents.count) events", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
        }
    }
}
