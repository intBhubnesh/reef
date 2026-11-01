import Foundation
import ReefCore

struct ManagedHookManifest: Codable {
    struct Entry: Codable {
        let installedAt: Date
        let events: [String]
        let command: String
    }
    var sources: [String: Entry] = [:]
}

enum HookManifestStore {
    static func load() -> ManagedHookManifest {
        guard let data = try? Data(contentsOf: Paths.hookManifestFile),
              let value = try? JSONDecoder().decode(ManagedHookManifest.self, from: data)
        else { return ManagedHookManifest() }
        return value
    }

    static func record(_ source: AgentSource) {
        var manifest = load()
        manifest.sources[source.rawValue] = .init(installedAt: Date(),
                                                   events: HookConfig.events(for: source),
                                                   command: HookConfig.command(source: source))
        save(manifest)
    }

    static func remove(_ source: AgentSource) {
        var manifest = load()
        manifest.sources[source.rawValue] = nil
        save(manifest)
    }

    private static func save(_ manifest: ManagedHookManifest) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(manifest) else { return }
        try? FileManager.default.createDirectory(at: Paths.supportDir, withIntermediateDirectories: true)
        try? data.write(to: Paths.hookManifestFile, options: .atomic)
    }
}
