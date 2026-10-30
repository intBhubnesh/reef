import AppKit
import ReefCore
import SwiftUI

/// Borderless, non-activating panel that floats over the menu bar on every Space.
final class NotchPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Sizes the panel to the pill when collapsed and to the full panel rect when expanded.
@MainActor
final class NotchWindowController {
    let panel: NotchPanel
    private let state: AppState
    private(set) var geometry: NotchGeometry
    private(set) var screenFrame: NSRect
    private var expanded = false
    private var collapseWorkItem: DispatchWorkItem?

    init(state: AppState) {
        self.state = state
        let screen = NSScreen.main ?? NSScreen.screens[0]
        screenFrame = screen.frame
        geometry = Self.geometry(for: screen, settings: state.settings)
        panel = NotchPanel(frame: Self.appKitRect(geometry.pillRect, in: screenFrame))
        let host = NSHostingView(rootView: NotchHostView(controller: self).environment(state))
        host.frame = panel.contentView!.bounds
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.relayout() }
        }
    }

    static func geometry(for screen: NSScreen, settings: ReefSettings) -> NotchGeometry {
        var auxLeft: CGRect?, auxRight: CGRect?
        if #available(macOS 12.0, *) {
            auxLeft = screen.auxiliaryTopLeftArea
            auxRight = screen.auxiliaryTopRightArea
        }
        return NotchGeometry.compute(screen: screen.frame, safeTop: screen.safeAreaInsets.top, auxLeft: auxLeft, auxRight: auxRight,
                                     panelMax: CGSize(width: settings.panelMaxWidth, height: settings.panelMaxHeight))
    }

    /// Converts a top-left-origin rect (relative to the screen) into AppKit screen coordinates.
    static func appKitRect(_ rect: CGRect, in screen: NSRect) -> NSRect {
        NSRect(x: screen.minX + rect.minX, y: screen.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    var pillScreenRect: NSRect { Self.appKitRect(geometry.pillRect, in: screenFrame) }
    /// The panel as drawn. Mouse tracking uses this, not the oversized window.
    var panelScreenRect: NSRect { Self.appKitRect(geometry.panelRect, in: screenFrame) }
    /// The window, which carries slack for the expansion's overshoot.
    var windowScreenRect: NSRect { Self.appKitRect(geometry.windowRect(expanded: expanded), in: screenFrame) }
    var isExpanded: Bool { expanded }

    func show() {
        panel.setFrame(pillScreenRect, display: true)
        panel.orderFrontRegardless()
    }

    func relayout() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        screenFrame = screen.frame
        geometry = Self.geometry(for: screen, settings: state.settings)
        panel.setFrame(windowScreenRect, display: true)
    }

    /// Grow the window before the spring starts, and shrink it only once the collapse has fully
    /// settled: the measured tail runs to ~600 ms, so an earlier shrink would clip it.
    func refresh() {
        let shouldExpand = state.notch.state.isExpanded
        guard shouldExpand != expanded else { return }
        expanded = shouldExpand
        collapseWorkItem?.cancel()
        if shouldExpand {
            panel.setFrame(windowScreenRect, display: true)
            panel.makeKey()
        } else {
            let item = DispatchWorkItem { [weak self] in
                guard let self, !self.expanded else { return }
                self.panel.setFrame(self.pillScreenRect, display: true)
            }
            collapseWorkItem = item
            let settle = Motion.collapseResponse + Motion.windowShrinkExtra
            DispatchQueue.main.asyncAfter(deadline: .now() + settle, execute: item)
        }
    }
}
