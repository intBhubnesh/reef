import Foundation
import ServiceManagement

/// Launch at login via SMAppService. Only meaningful from a signed .app bundle; best effort otherwise.
enum LaunchAtLogin {
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static var isEnabled: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) -> String? {
        guard isAvailable else { return "Launch at login needs the Reef.app bundle (run scripts/bundle.sh)." }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            Log.warn("app", "launch at login failed", ["error": "\(error)"])
            return error.localizedDescription
        }
    }
}
