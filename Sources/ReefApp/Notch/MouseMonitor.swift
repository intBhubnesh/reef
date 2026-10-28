import AppKit

/// Translates global/local mouse and key events into notch intents.
@MainActor
final class MouseMonitor {
    private let state: AppState
    private let controller: NotchWindowController
    private var monitors: [Any] = []
    private var inside = false

    init(state: AppState, controller: NotchWindowController) {
        self.state = state
        self.controller = controller
    }

    func start() {
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in self?.mouseMoved() }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor in self?.mouseMoved() }
            return event
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.globalClick() }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // esc
                Task { @MainActor in self?.state.escape() }
                return nil
            }
            return event
        } as Any)
    }

    private var hotRect: NSRect {
        controller.isExpanded ? controller.panel.frame : controller.pillScreenRect
    }

    private func mouseMoved() {
        let now = hotRect.contains(NSEvent.mouseLocation)
        guard now != inside else { return }
        inside = now
        state.hover(inside: now)
    }

    private func globalClick() {
        if !controller.panel.frame.contains(NSEvent.mouseLocation) { state.outsideClick() }
    }
}
