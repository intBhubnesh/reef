import Foundation
import ReefCore

/// Self-healing: every 2.5 s, re-add Reef's hook entries for agents the user installed if they went missing.
@MainActor
final class HookWatcher {
    private var timer: Timer?
    private let installedSources: () -> [AgentSource]
    private let onHealed: (AgentSource) -> Void

    init(installedSources: @escaping () -> [AgentSource], onHealed: @escaping (AgentSource) -> Void) {
        self.installedSources = installedSources
        self.onHealed = onHealed
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
    }

    func stop() { timer?.invalidate() }

    func check() {
        for source in installedSources() where !HookInstaller.status(source).isComplete {
            if HookInstaller.install(source) == nil {
                Log.warn("hook", "restored missing hook entries", ["source": source.rawValue])
                onHealed(source)
            }
        }
    }
}
