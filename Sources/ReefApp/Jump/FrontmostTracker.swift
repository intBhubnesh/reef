import AppKit
import ReefCore

/// Tracks the frontmost application so approvals can follow the user's focus.
@MainActor
final class FrontmostTracker {
    private(set) var frontmostBundleID: String?
    var onActivation: ((String?) -> Void)?
    private var observer: NSObjectProtocol?

    init() {
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundle = app?.bundleIdentifier
            Task { @MainActor in
                self?.frontmostBundleID = bundle
                self?.onActivation?(bundle)
            }
        }
    }

    /// App match, plus the focused kitty window when kitty remote control can tell us.
    func isFrontmost(_ terminal: TerminalIdentity) -> Bool {
        guard let bundle = terminal.bundleID, bundle == frontmostBundleID else { return false }
        var focusedKitty: Set<Int>?
        if terminal.kittyWindowID != nil {
            focusedKitty = KittyRemote.focusedWindowIDs(listenOn: terminal.kittyListenOn ?? terminal.kittyPID.map { "unix:/tmp/kitty-\($0)" })
        }
        return FocusMatch.isFocused(terminal, frontmostBundleID: frontmostBundleID, focusedKittyWindows: focusedKitty)
    }
}
