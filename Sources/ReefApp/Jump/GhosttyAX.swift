import AppKit
import ApplicationServices
import ReefCore

/// Ghostty has no remote control: find the window or tab whose title carries the session marker via Accessibility.
enum GhosttyAX {
    enum Result { case focused, notFound, accessibilityDenied }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func focus(marker: String) -> Result {
        guard isTrusted else { requestAccess(); return .accessibilityDenied }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: JumpPlanner.ghosttyBundle).first else {
            return .notFound
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        for window in children(of: axApp, attribute: kAXWindowsAttribute) {
            if (title(of: window) ?? "").contains(marker) {
                raise(window)
                return .focused
            }
            for tab in tabs(in: window) where (title(of: tab) ?? "").contains(marker) {
                raise(window)
                AXUIElementPerformAction(tab, kAXPressAction as CFString)
                return .focused
            }
        }
        return .notFound
    }

    private static func raise(_ window: AXUIElement) {
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    private static func title(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func children(of element: AXUIElement, attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    /// Tab buttons anywhere under the window (tab groups, toolbars), depth-limited.
    private static func tabs(in window: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 6 else { return [] }
        var found: [AXUIElement] = []
        for child in children(of: window, attribute: kAXChildrenAttribute) {
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
            if (role as? String) == kAXRadioButtonRole || (role as? String) == "AXTab" || (role as? String) == kAXButtonRole {
                found.append(child)
            }
            found += tabs(in: child, depth: depth + 1)
        }
        return found
    }
}
