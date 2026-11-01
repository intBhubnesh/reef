import AppKit
import ReefCore
import SwiftUI

struct Chip: View {
    let text: String
    var tint: Color = Theme.textSecondary
    var background: Color = Theme.chip

    var body: some View {
        Text(text)
            .font(Theme.chipFont)
            .foregroundStyle(tint)
            .frame(height: Metrics.chipHeight)
            .padding(.horizontal, Metrics.chipPadding)
            .background(background, in: Capsule())
    }
}

/// Compact source badge used where the cards previously spelled out "Claude" or "Codex".
/// The marks come from the bundled, attributed upstream vector assets.
struct AgentIconChip: View {
    let source: AgentSource
    var tint: Color?
    var background: Color?

    var body: some View {
        let colors = Theme.chipColors(source)
        AgentMark(source: source, color: tint ?? colors.text)
            .frame(width: 11, height: 11)
            .frame(width: 22, height: Metrics.chipHeight)
            .background(background ?? colors.background, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AgentLabel.name(source))
            .help(AgentLabel.name(source))
    }
}

/// Shared provider mark used by both session chips and the usage header.
struct AgentMark: View {
    let source: AgentSource
    let color: Color

    var body: some View {
        BundledBrandMark(name: source == .claude ? "Claude" : "Codex",
                         template: true,
                         fallbackSymbol: source == .claude ? "sparkles" : "terminal.fill")
            .foregroundStyle(color)
    }
}

/// Terminal host badge. The first supported hosts use icons; unknown hosts keep the existing
/// text chip until they receive a dedicated mark.
struct TerminalBadge: View {
    let terminal: TerminalIdentity

    var body: some View {
        if let brand = TerminalBrand(terminal) {
            TerminalIconChip(brand: brand)
        } else if let name = AgentLabel.terminalName(terminal) {
            Chip(text: name)
        }
    }
}

private enum TerminalBrand {
    case terminal
    case kitty
    case warp
    case vscode

    init?(_ terminal: TerminalIdentity) {
        let program = terminal.termProgram?.lowercased() ?? ""
        let bundle = terminal.bundleID?.lowercased() ?? ""
        if program == "kitty" || bundle == "net.kovidgoyal.kitty" { self = .kitty }
        else if program == "apple_terminal" || bundle == "com.apple.terminal" { self = .terminal }
        else if program.contains("warp") || bundle.contains("warp") { self = .warp }
        else if program == "vscode" || bundle == "com.microsoft.vscode" { self = .vscode }
        else { return nil }
    }

    var name: String {
        switch self {
        case .terminal: return "Terminal"
        case .kitty: return "Kitty"
        case .warp: return "Warp"
        case .vscode: return "VS Code"
        }
    }
}

private struct TerminalIconChip: View {
    let brand: TerminalBrand

    var body: some View {
        terminalMark
            .foregroundStyle(Theme.textSecondary)
            .frame(width: 11, height: 11)
            .frame(width: 22, height: Metrics.chipHeight)
            .background(Theme.chip, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(brand.name)
            .help(brand.name)
    }

    @ViewBuilder private var terminalMark: some View {
        switch brand {
        case .terminal:
            Image(systemName: "terminal.fill")
                .font(.system(size: 8.5, weight: .semibold))
        case .kitty:
            Image(systemName: "cat.fill")
                .font(.system(size: 9, weight: .semibold))
        case .warp:
            BundledBrandMark(name: "Warp", template: true, fallbackSymbol: "w.square.fill")
        case .vscode:
            BundledBrandMark(name: "VSCode", fileExtension: "png", template: false,
                             fallbackSymbol: "chevron.left.forwardslash.chevron.right")
        }
    }
}

/// Loads a bundled rendering of an attributed upstream SVG. Most marks remain vector PDFs;
/// multicolour artwork can use a high-resolution PNG when AppKit cannot preserve its SVG paint.
private struct BundledBrandMark: View {
    let name: String
    let fileExtension: String
    let template: Bool
    let fallbackSymbol: String

    init(name: String, fileExtension: String = "pdf", template: Bool, fallbackSymbol: String) {
        self.name = name
        self.fileExtension = fileExtension
        self.template = template
        self.fallbackSymbol = fallbackSymbol
    }

    var body: some View {
        if let url = Bundle.main.url(forResource: name, withExtension: fileExtension,
                                     subdirectory: "BrandIcons"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .renderingMode(template ? .template : .original)
                .scaledToFit()
        } else {
            Image(systemName: fallbackSymbol)
                .resizable()
                .scaledToFit()
        }
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
        case .some(let id) where id.lowercased().contains("warp"): return "Warp"
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
