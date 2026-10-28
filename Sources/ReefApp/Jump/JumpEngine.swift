import AppKit
import ReefCore

/// Runs jump steps in order until one succeeds; each outcome is logged under `jump`.
@MainActor
final class JumpEngine {
    var needsAccessibility = false

    @discardableResult
    func run(_ steps: [JumpStep]) async -> JumpStep? {
        var succeeded: JumpStep?
        for step in steps {
            let ok = await perform(step)
            Log.info("jump", "step", ["step": describe(step), "ok": ok ? "1" : "0"])
            if ok {
                succeeded = step
                if case .tmuxSelectPane = step { continue } // tmux selection complements the terminal focus
                if case .activateApp = step { break }
                // A precise focus still needs the app in front.
                if let bundle = steps.compactMap({ if case let .activateApp(id) = $0 { return id }; return nil }).first {
                    _ = Self.activate(bundleID: bundle)
                }
                if !steps.contains(where: { if case .tmuxSelectPane = $0 { return true }; return false }) { break }
            }
        }
        return succeeded
    }

    private func perform(_ step: JumpStep) async -> Bool {
        switch step {
        case let .kittyFocusWindow(id, listenOn):
            return await KittyRemote.focusWindow(id: id, listenOn: listenOn)
        case let .ghosttyFocusByTitleMarker(marker):
            _ = Self.activate(bundleID: JumpPlanner.ghosttyBundle)
            let result = GhosttyAX.focus(marker: marker)
            if result == .accessibilityDenied { needsAccessibility = true }
            return result == .focused
        case let .vscodeOpen(cwd):
            return await Shell.run("/usr/bin/open", ["-b", JumpPlanner.vscodeBundle, cwd]) == 0
        case let .tmuxSelectPane(pane):
            return await TmuxFocus.select(pane: pane)
        case let .activateApp(bundleID):
            return Self.activate(bundleID: bundleID)
        }
    }

    static func activate(bundleID: String) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return false }
        return app.activate()
    }

    private func describe(_ step: JumpStep) -> String {
        switch step {
        case let .kittyFocusWindow(id, _): return "kitty:\(id)"
        case let .ghosttyFocusByTitleMarker(m): return "ghostty:\(m)"
        case let .vscodeOpen(cwd): return "vscode:\(cwd)"
        case let .tmuxSelectPane(p): return "tmux:\(p)"
        case let .activateApp(b): return "activate:\(b)"
        }
    }
}

enum Shell {
    /// Runs an executable and returns its exit status, or -1 when it cannot start or exceeds the timeout.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 3) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let once = Once()
            process.terminationHandler = { p in
                if once.claim() { continuation.resume(returning: p.terminationStatus) }
            }
            do { try process.run() } catch {
                if once.claim() { continuation.resume(returning: -1) }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning, once.claim() else { return }
                process.terminate()
                continuation.resume(returning: -1)
            }
        }
    }

    /// Thread-safe one-shot flag so a continuation resumes exactly once.
    final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false
        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if claimed { return false }
            claimed = true
            return true
        }
    }

    static func which(_ name: String, extra: [String] = []) -> String? {
        let candidates = extra + ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
