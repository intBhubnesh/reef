import Foundation
import ReefCore

/// Intent-aware health check. Reef repairs only integrations the user explicitly installed and
/// never overwrites malformed configuration that needs human inspection.
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
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
    }

    func stop() { timer?.invalidate() }

    func check() {
        for source in installedSources() {
            let health = HookInstaller.health(source)
            guard !health.isHealthy, health.isAutoRepairable else { continue }
            if HookInstaller.install(source) == nil {
                Log.warn("hook", "restored missing hook entries", ["source": source.rawValue])
                onHealed(source)
            }
        }
    }
}
