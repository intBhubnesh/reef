import Foundation

/// Decides whether the user is looking at a session's terminal: the app must be frontmost, and for kitty
/// (when the focused window ids are known) the session's window must be the focused one.
public enum FocusMatch {
    public static func isFocused(_ terminal: TerminalIdentity, frontmostBundleID: String?, focusedKittyWindows: Set<Int>?) -> Bool {
        guard let bundle = terminal.bundleID, bundle == frontmostBundleID else { return false }
        if let windowID = terminal.kittyWindowID, let focused = focusedKittyWindows {
            return focused.contains(windowID)
        }
        return true
    }
}
