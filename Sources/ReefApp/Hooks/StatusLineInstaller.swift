import Foundation
import ReefCore

/// Installs the status-line shim that feeds Reef's usage header, but only into an empty slot.
/// Claude Code has exactly one `statusLine`, so if another app owns it Reef leaves it alone and
/// says so rather than silently breaking that app.
enum StatusLineInstaller {
    static var shimPath: URL { Paths.binDir.appendingPathComponent("reef-statusline") }
    static var cachePath: URL { Paths.cacheDir.appendingPathComponent("rl.json") }

    static func state() -> StatusLineState {
        let root = HookFiles.read(file: Paths.claudeSettings) ?? [:]
        let command = (root["statusLine"] as? [String: Any])?["command"] as? String
        return StatusLineState.of(command: command)
    }

    /// Writes the shim and claims the slot. Returns an error message when the slot is taken.
    @discardableResult
    static func install() -> String? {
        switch state() {
        case .ownedByReef: return nil
        case let .ownedByOther(command):
            return "Another app owns Claude Code's status line (\(command)). Reef left it untouched."
        case .free:
            break
        }
        guard writeShim() == nil else { return "Could not write \(shimPath.path)." }
        let ok = HookFiles.transform(file: Paths.claudeSettings) { root in
            var root = root
            root["statusLine"] = ["type": "command", "command": shimPath.path, "padding": 0]
            return root
        }
        Log.info("usage", ok ? "status line installed" : "status line install failed")
        return ok ? nil : "Could not update \(Paths.claudeSettings)."
    }

    @discardableResult
    static func uninstall() -> String? {
        guard state() == .ownedByReef else { return nil }
        let ok = HookFiles.transform(file: Paths.claudeSettings) { root in
            var root = root
            root["statusLine"] = nil
            return root
        }
        try? FileManager.default.removeItem(at: shimPath)
        return ok ? nil : "Could not update \(Paths.claudeSettings)."
    }

    /// A tiny shell wrapper, so the user can read exactly what Reef put in their config.
    private static func writeShim() -> Error? {
        let bridge = Paths.bridgeBinary.path
        let script = """
        #!/bin/sh
        # Installed by Reef. Caches Claude Code's rate limits for the notch header and
        # passes the status line through unchanged. Remove it from Settings > Integrations.
        exec "\(bridge)" --task statusline-cache --cache-file "\(cachePath.path)"
        """
        do {
            try FileManager.default.createDirectory(at: Paths.binDir, withIntermediateDirectories: true)
            try script.write(to: shimPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shimPath.path)
            return nil
        } catch {
            return error
        }
    }
}

/// Polls the cache the shim writes.
@MainActor
final class UsageReader {
    private var timer: Timer?
    private let onUpdate: (UsageSnapshot?) -> Void

    init(onUpdate: @escaping (UsageSnapshot?) -> Void) {
        self.onUpdate = onUpdate
    }

    func start() {
        read()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.read() }
        }
    }

    func stop() { timer?.invalidate() }

    private func read() {
        let url = StatusLineInstaller.cachePath
        guard let data = try? Data(contentsOf: url),
              let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        else { return onUpdate(nil) }
        onUpdate(UsageSnapshot.parse(data, now: modified))
    }
}
