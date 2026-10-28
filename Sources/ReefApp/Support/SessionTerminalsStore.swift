import Foundation
import ReefCore

/// Persists session → terminal identity so a jump still works after Reef relaunches.
final class SessionTerminalsStore {
    private let url: URL
    private var entries: [String: TerminalIdentity]

    init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([String: TerminalIdentity].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    private func id(_ key: SessionKey) -> String { "\(key.source.rawValue):\(key.sessionID)" }

    func identity(for key: SessionKey) -> TerminalIdentity? { entries[id(key)] }

    func remember(_ identity: TerminalIdentity, for key: SessionKey) {
        guard !identity.isHeadless else { return }
        entries[id(key)] = identity
        if entries.count > 500 { entries = Dictionary(uniqueKeysWithValues: Array(entries.suffix(400))) }
        save()
    }

    func forget(_ key: SessionKey) {
        entries[id(key)] = nil
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entries) { try? data.write(to: url, options: .atomic) }
    }
}
