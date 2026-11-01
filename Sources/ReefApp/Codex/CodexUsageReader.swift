import Foundation
import ReefCore

/// Reads Codex's account rate limits from the newest rollout transcript tails. This is separate
/// from session discovery: review/subagent transcripts are deliberately hidden as cards, but
/// their token-count records still contain the same useful account-level limits.
@MainActor
final class CodexUsageReader {
    static let pollInterval: TimeInterval = 5
    static let lookback: TimeInterval = 60 * 60
    static let tailRead = 8 << 20
    static let candidateLimit = 12

    private let root: URL
    private let onUpdate: (UsageSnapshot?) -> Void
    private var timer: Timer?
    private var lastSnapshot: UsageSnapshot?

    init(root: URL, onUpdate: @escaping (UsageSnapshot?) -> Void) {
        self.root = root
        self.onUpdate = onUpdate
    }

    func start() {
        guard timer == nil else { return }
        read()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.read() }
        }
        Log.info("codex", "watching usage", ["root": root.path])
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func read() {
        var newest: UsageSnapshot?
        for url in recentTranscripts().prefix(Self.candidateLimit) {
            guard let snapshot = snapshot(at: url) else { continue }
            if newest == nil || snapshot.capturedAt > newest!.capturedAt { newest = snapshot }
        }
        if newest != lastSnapshot {
            Log.info("codex", "usage updated", [
                "five_hour": newest?.fiveHour.map { "\($0.usedPercent)%" } ?? "-",
                "seven_day": newest?.sevenDay.map { "\($0.usedPercent)%" } ?? "-"
            ])
            lastSnapshot = newest
        }
        onUpdate(newest)
    }

    private func snapshot(at url: URL) -> UsageSnapshot? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd(), end > 0 else { return nil }
        let start = end > UInt64(Self.tailRead) ? end - UInt64(Self.tailRead) : 0
        guard (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty
        else { return nil }
        return UsageSnapshot.latestCodexSnapshot(in: data)
    }

    private func recentTranscripts() -> [URL] {
        let cutoff = Date().addingTimeInterval(-Self.lookback)
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        var found: [(URL, Date)] = []
        for case let url as URL in walker
            where url.lastPathComponent.hasPrefix("rollout-") && url.pathExtension == "jsonl" {
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate, modified > cutoff else { continue }
            found.append((url, modified))
        }
        return found.sorted { $0.1 > $1.1 }.map(\.0)
    }
}
