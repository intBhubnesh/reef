import AppKit

/// Translates global/local mouse and key events into notch intents.
@MainActor
final class MouseMonitor {
    private let state: AppState
    private let controller: NotchWindowController
    private var monitors: [Any] = []
    private var inside = false
    private var pressingInside = false
    private var exitWorkItem: DispatchWorkItem?
    private var lastMoveAt: TimeInterval = 0

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
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if self.hotRect.contains(NSEvent.mouseLocation) {
                if event.type == .leftMouseDown { self.pressingInside = true }
                self.exitWorkItem?.cancel()
            } else {
                Task { @MainActor in self.state.outsideClick() }
            }
            return event
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.finishPress()
            return event
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            Task { @MainActor in self?.finishPress() }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, let shortcut = PanelShortcut.from(event: event), self.controller.isExpanded else { return event }
            Task { @MainActor in self.state.perform(shortcut) }
            return nil
        } as Any)
    }

    /// The drawn panel, not the oversized window: the overshoot headroom is empty space and
    /// must not count as "the pointer is inside".
    private var hotRect: NSRect {
        controller.isExpanded ? controller.panelScreenRect : controller.pillScreenRect
    }

    private func mouseMoved(force: Bool = false) {
        let timestamp = ProcessInfo.processInfo.systemUptime
        guard force || timestamp - lastMoveAt >= 0.05 else { return }
        lastMoveAt = timestamp
        let now = hotRect.contains(NSEvent.mouseLocation)
        guard now != inside else { return }
        if now {
            exitWorkItem?.cancel()
            inside = true
            state.surfaceEntered()
            state.hover(inside: true)
        } else {
            // A tiny cancellation grace prevents the concave top edge and display seam from
            // producing a rapid leave/enter loop.
            exitWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self,
                      !self.pressingInside,
                      !self.hotRect.contains(NSEvent.mouseLocation) else { return }
                self.inside = false
                self.state.hover(inside: false)
            }
            exitWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: item)
        }
    }

    private func globalClick() {
        if !hotRect.contains(NSEvent.mouseLocation) { state.outsideClick() }
    }

    private func finishPress() {
        guard pressingInside else { return }
        pressingInside = false
        // Re-evaluate after SwiftUI has delivered the mouse-up action. This keeps a control
        // mounted for the complete click without adding any visible close delay.
        DispatchQueue.main.async { [weak self] in self?.mouseMoved(force: true) }
    }
}
