import Foundation

public enum JumpStep: Equatable {
    case kittyFocusWindow(id: Int, listenOn: String?)
    case ghosttyFocusByTitleMarker(String)
    case vscodeOpen(cwd: String)
    case tmuxSelectPane(String)
    case terminalFocusTTY(String)
    case iTermFocusTTY(String)
    case weztermFocusPane(Int)
    case activateApp(bundleID: String)
}

/// Ordered jump steps for a session's terminal; the engine runs them until one succeeds.
public enum JumpPlanner {
    public static let kittyBundle = "net.kovidgoyal.kitty"
    public static let ghosttyBundle = "com.mitchellh.ghostty"
    public static let vscodeBundle = "com.microsoft.VSCode"
    public static let terminalBundle = "com.apple.Terminal"
    public static let iTermBundle = "com.googlecode.iterm2"
    public static let weztermBundle = "com.github.wez.wezterm"

    public static func plan(_ t: TerminalIdentity, cwd: String?) -> [JumpStep] {
        guard !t.isHeadless else { return [] }
        var steps: [JumpStep] = []
        if let id = t.kittyWindowID {
            steps.append(.kittyFocusWindow(id: id, listenOn: t.kittyListenOn ?? t.kittyPID.map { "unix:/tmp/kitty-\($0)" }))
        }
        if t.termProgram?.lowercased() == "ghostty" || t.bundleID == ghosttyBundle, let marker = t.ghosttyMarker {
            steps.append(.ghosttyFocusByTitleMarker(marker))
        }
        if t.bundleID == vscodeBundle || t.vscodePID != nil, let cwd {
            steps.append(.vscodeOpen(cwd: cwd))
        }
        if let pane = t.tmuxPane {
            steps.append(.tmuxSelectPane(pane))
        }
        if t.bundleID == terminalBundle, let tty = t.tty {
            steps.append(.terminalFocusTTY(tty))
        }
        if t.bundleID == iTermBundle, let tty = t.tty {
            steps.append(.iTermFocusTTY(tty))
        }
        if t.bundleID == weztermBundle, let pane = t.weztermPaneID {
            steps.append(.weztermFocusPane(pane))
        }
        if let bundleID = t.bundleID {
            steps.append(.activateApp(bundleID: bundleID))
        }
        return steps
    }
}
