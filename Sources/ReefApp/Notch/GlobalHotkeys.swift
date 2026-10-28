import AppKit
import CoreGraphics

/// Panel shortcuts without stealing focus: a session-level CGEvent tap swallows ⌃Y/⌃N/⌃A/⌃T/⌃↩/esc while the
/// panel is expanded. Needs Accessibility; when it is missing the local NSEvent monitor still works whenever
/// a Reef window is key.
@MainActor
final class GlobalHotkeys {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let isActive: () -> Bool
    private let perform: (PanelShortcut) -> Void

    init(isActive: @escaping () -> Bool, perform: @escaping (PanelShortcut) -> Void) {
        self.isActive = isActive
        self.perform = perform
    }

    var isInstalled: Bool { tap != nil }

    func start() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, userInfo in
                                              guard let userInfo else { return Unmanaged.passUnretained(event) }
                                              let hotkeys = Unmanaged<GlobalHotkeys>.fromOpaque(userInfo).takeUnretainedValue()
                                              return hotkeys.handle(type: type, event: event)
                                          }, userInfo: selfPtr)
        else {
            Log.warn("ui", "event tap unavailable")
            return
        }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.info("ui", "event tap installed")
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    private nonisolated func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Task { @MainActor in if let tap = self.tap { CGEvent.tapEnable(tap: tap, enable: true) } }
            return Unmanaged.passUnretained(event)
        }
        guard let nsEvent = NSEvent(cgEvent: event), let shortcut = PanelShortcut.from(event: nsEvent) else {
            return Unmanaged.passUnretained(event)
        }
        let handled = MainActor.assumeIsolated { () -> Bool in
            guard isActive() else { return false }
            perform(shortcut)
            return true
        }
        return handled ? nil : Unmanaged.passUnretained(event)
    }
}
