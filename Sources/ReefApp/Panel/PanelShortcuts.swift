import AppKit

/// Keyboard shortcuts active while the panel is expanded; applied to the oldest pending request.
enum PanelShortcut: Equatable {
    case allow, deny, alwaysAllow, jump, submit, collapse

    static func from(event: NSEvent) -> PanelShortcut? {
        if event.keyCode == 53 { return .collapse }
        guard event.modifierFlags.contains(.control) else { return nil }
        if event.keyCode == 36 { return .submit } // return
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "y": return .allow
        case "n": return .deny
        case "a": return .alwaysAllow
        case "t": return .jump
        default: return nil
        }
    }
}
