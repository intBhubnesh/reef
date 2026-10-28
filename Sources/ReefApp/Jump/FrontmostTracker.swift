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

    /// Bundle match only: a precise window/tab check would need remote control or Accessibility on every event.
    func isFrontmost(_ terminal: TerminalIdentity) -> Bool {
        guard let bundle = terminal.bundleID, let front = frontmostBundleID else { return false }
        return bundle == front
    }
}
