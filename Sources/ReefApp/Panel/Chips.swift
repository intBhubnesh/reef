import ReefCore
import SwiftUI

struct Chip: View {
    let text: String
    var tint: Color = Theme.textSecondary
    var background: Color = Theme.chip

    var body: some View {
        Text(text)
            .font(Theme.small.weight(.medium))
            .foregroundStyle(tint)
            .frame(height: Metrics.chipHeight)
            .padding(.horizontal, 7)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

enum AgentLabel {
    static func name(_ source: AgentSource) -> String {
        source == .claude ? "Claude" : "Codex"
    }

    static func terminalName(_ t: TerminalIdentity) -> String? {
        if let program = t.termProgram?.lowercased() {
            switch program {
            case "kitty": return "Kitty"
            case "ghostty": return "Ghostty"
            case "iterm.app": return "iTerm"
            case "apple_terminal": return "Terminal"
            case "warpterminal": return "Warp"
            case "wezterm": return "WezTerm"
            case "vscode": return "VS Code"
            default: break
            }
        }
        switch t.bundleID {
        case "net.kovidgoyal.kitty": return "Kitty"
        case "com.mitchellh.ghostty": return "Ghostty"
        case "com.microsoft.VSCode": return "VS Code"
        case "com.googlecode.iterm2": return "iTerm"
        case "com.apple.Terminal": return "Terminal"
        case .some(let id): return id.split(separator: ".").last.map(String.init)
        case .none: return nil
        }
    }
}

struct PanelButtonStyle: ButtonStyle {
    enum Role { case primary, secondary, quiet, danger }
    let role: Role

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body.weight(.semibold))
            .foregroundStyle(role == .quiet ? Theme.textSecondary : (role == .primary ? Color.black : Theme.textPrimary))
            .padding(.horizontal, role == .quiet ? 6 : 14)
            .padding(.vertical, 7)
            .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }

    private var background: Color {
        switch role {
        case .primary: return Theme.accent
        case .secondary: return Theme.chip
        case .danger: return Theme.failed.opacity(0.25)
        case .quiet: return .clear
        }
    }
}
