import AppKit
import CoreGraphics

struct OverlayDisplayOption: Identifiable, Equatable {
    static let automaticID = "automatic"
    let id: String
    let title: String
    let connected: Bool
}

enum OverlayDisplayResolver {
    static func stableID(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))
        else { return nil }
        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
    }

    static func options(preferredID: String) -> [OverlayDisplayOption] {
        var result = [OverlayDisplayOption(id: OverlayDisplayOption.automaticID,
                                           title: "Automatic (prefer built-in notch)", connected: true)]
        for (index, screen) in NSScreen.screens.enumerated() {
            guard let id = stableID(for: screen) else { continue }
            let name = screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName
            result.append(OverlayDisplayOption(id: id, title: name, connected: true))
        }
        if preferredID != OverlayDisplayOption.automaticID,
           !result.contains(where: { $0.id == preferredID }) {
            result.append(OverlayDisplayOption(id: preferredID, title: "Disconnected display", connected: false))
        }
        return result
    }

    static func resolve(preferredID: String) -> NSScreen? {
        if preferredID != OverlayDisplayOption.automaticID,
           let exact = NSScreen.screens.first(where: { stableID(for: $0) == preferredID }) {
            return exact
        }
        return NSScreen.screens.first(where: hasPhysicalNotch)
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private static func hasPhysicalNotch(_ screen: NSScreen) -> Bool {
        guard screen.safeAreaInsets.top > 0 else { return false }
        if #available(macOS 12.0, *) {
            return screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
        }
        return false
    }
}
