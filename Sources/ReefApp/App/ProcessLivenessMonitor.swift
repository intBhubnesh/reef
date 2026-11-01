import Foundation
import ReefCore

/// Low-frequency, coarse process discovery. It intentionally reports only source presence;
/// terminal matching remains a separate jump concern and hook UUIDs remain authoritative IDs.
@MainActor
final class ProcessLivenessMonitor {
    struct Snapshot {
        var processIDs: Set<Int> = []
        var sources: Set<AgentSource> = []
    }

    private var workItem: DispatchWorkItem?
    private let hasActiveSessions: () -> Bool
    private let onSnapshot: (Snapshot) -> Void
    private let startedAt = Date()
    private var stopped = false

    init(hasActiveSessions: @escaping () -> Bool,
         onSnapshot: @escaping (Snapshot) -> Void) {
        self.hasActiveSessions = hasActiveSessions
        self.onSnapshot = onSnapshot
    }

    func start() { stopped = false; poll() }

    func stop() {
        stopped = true
        workItem?.cancel()
    }

    private func poll() {
        guard !stopped else { return }
        Task.detached(priority: .utility) {
            let snapshot = Self.readSnapshot()
            await MainActor.run { [weak self] in
                guard let self, !self.stopped else { return }
                self.onSnapshot(snapshot)
                self.scheduleNext()
            }
        }
    }

    private func scheduleNext() {
        let age = Date().timeIntervalSince(startedAt)
        let interval: TimeInterval = age < 20 ? 2 : (hasActiveSessions() ? 60 : 300)
        let item = DispatchWorkItem { [weak self] in self?.poll() }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: item)
    }

    nonisolated private static func readSnapshot() -> Snapshot {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return Snapshot() }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        else { return Snapshot() }
        var result = Snapshot()
        for line in text.split(separator: "\n") {
            let fields = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard let first = fields.first, let pid = Int(first) else { continue }
            result.processIDs.insert(pid)
            guard fields.count == 2 else { continue }
            let command = fields[1].lowercased()
            if command.contains("claude") { result.sources.insert(.claude) }
            if command.contains("codex") { result.sources.insert(.codex) }
        }
        return result
    }
}
