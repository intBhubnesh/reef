import AppKit
import ReefCore
import SwiftUI

/// Borderless, non-activating panel that floats over the menu bar on every Space.
final class NotchPanel: NSPanel {
    /// Handles controls that must work on the activation click of this non-activating panel.
    var firstMouseDownHandler: ((NSPoint) -> Bool)?

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

    /// Hover/notification opens deliberately avoid activation. Promote the panel on the first
    /// real click so controls receive that click instead of requiring a second one.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           firstMouseDownHandler?(NSEvent.mouseLocation) == true {
            return
        }
        if event.type == .leftMouseDown, !isKeyWindow {
            // `makeKey()` alone is not enough for an accessory application when another app is
            // active: SwiftUI sees the press as activation-only and its Button never receives
            // the matching mouse-up. Activate only after a real click, never on hover/open.
            NSApp.activate(ignoringOtherApps: true)
            makeKeyAndOrderFront(nil)
        }
        super.sendEvent(event)
    }
}

/// Owns one fixed maximum-size window. SwiftUI morphs the visible island inside it; changing the
/// AppKit frame during a spring creates clipping and hit-test races at exactly the wrong moment.
@MainActor
final class NotchWindowController {
    let panel: NotchPanel
    private let state: AppState
    private(set) var geometry: NotchGeometry
    private(set) var screenFrame: NSRect
    private var expanded = false
    private weak var hostingView: NSView?
    private var renderedPanelSize: CGSize

    init(state: AppState) {
        self.state = state
        let screen = OverlayDisplayResolver.resolve(preferredID: state.settings.preferredDisplayID)
            ?? NSScreen.main ?? NSScreen.screens[0]
        screenFrame = screen.frame
        geometry = Self.geometry(for: screen, settings: state.settings)
        renderedPanelSize = geometry.panelRect.size
        panel = NotchPanel(frame: Self.appKitRect(geometry.windowRect(expanded: true), in: screenFrame))
        panel.firstMouseDownHandler = { [weak self] point in
            guard let self,
                  self.expanded,
                  self.settingsButtonScreenRect.contains(point) else { return false }
            self.state.openSettings()
            return true
        }
        let host = NotchHostingView(rootView: NotchHostView(controller: self).environment(state))
        host.frame = panel.contentView!.bounds
        host.autoresizingMask = [.width, .height]
        host.visibleHitRect = { [weak self] in
            guard let self else { return .zero }
            return self.expanded ? self.panelScreenRect : self.pillScreenRect
        }
        panel.contentView = host
        hostingView = host
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
    var panelScreenRect: NSRect {
        // The expanded header is always laid out at the configured panel width. During mount,
        // SwiftUI can emit the pill's width through the size preference for one pass; trusting
        // that transient value leaves the visible controls at either edge outside AppKit's hit
        // region. Height remains measured so empty space below short content stays click-through.
        let size = CGSize(width: geometry.panelRect.width,
                          height: min(max(renderedPanelSize.height, Metrics.headerHeight),
                                      geometry.panelRect.height))
        let rect = CGRect(x: geometry.notchRect.midX - size.width / 2, y: 0,
                          width: size.width, height: size.height)
        return Self.appKitRect(rect, in: screenFrame)
    }
    /// Exact frame of the gear's SwiftUI label in AppKit screen coordinates. Routing this
    /// activation press at the panel layer avoids SwiftUI treating it as focus-only.
    var settingsButtonScreenRect: NSRect {
        let rect = panelScreenRect
        return NSRect(x: rect.maxX - Metrics.cardPadding - Metrics.headerGearSize - 10,
                      y: rect.maxY - Metrics.headerHeight,
                      width: Metrics.headerGearSize + 10,
                      height: Metrics.headerHeight)
    }
    /// The window, which carries slack for the expansion's overshoot.
    var windowScreenRect: NSRect { Self.appKitRect(geometry.windowRect(expanded: expanded), in: screenFrame) }
    var isExpanded: Bool { expanded }

    func updateRenderedPanelSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        renderedPanelSize = size
    }

    func show() {
        panel.setFrame(Self.appKitRect(geometry.windowRect(expanded: true), in: screenFrame), display: true)
        panel.orderFrontRegardless()
    }

    func relayout() {
        let screen = OverlayDisplayResolver.resolve(preferredID: state.settings.preferredDisplayID)
            ?? NSScreen.main ?? NSScreen.screens[0]
        screenFrame = screen.frame
        geometry = Self.geometry(for: screen, settings: state.settings)
        renderedPanelSize = geometry.panelRect.size
        panel.setFrame(Self.appKitRect(geometry.windowRect(expanded: true), in: screenFrame), display: true)
        hostingView?.needsLayout = true
    }

    func refresh() {
        let shouldExpand = state.notch.state.isExpanded
        guard shouldExpand != expanded else { return }
        expanded = shouldExpand
        Log.info("notch", shouldExpand ? "expand" : "collapse", ["transition": "\(state.notch.lastTransition)"])
        if shouldExpand, state.notch.openReason == .click {
            panel.makeKey()
        }
        hostingView?.needsLayout = true
    }
}

/// A transparent fixed window must not consume clicks in the empty area around the visible
/// island. AppKit asks the content view to hit-test before dispatching to SwiftUI, so returning
/// nil here gives the event back to the app underneath.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var visibleHitRect: (() -> NSRect)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let window, let visibleHitRect else { return super.hitTest(point) }
        let windowPoint = convert(point, to: nil)
        let screenPoint = window.convertPoint(toScreen: windowPoint)
        guard visibleHitRect().contains(screenPoint) else { return nil }
        return super.hitTest(point)
    }
}
