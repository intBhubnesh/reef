import Foundation
import ReefCore

/// Watches `~/.codex/sessions` so Codex front ends that do not run hooks, notably the VS Code
/// extension, still appear on the island. Reads each transcript incrementally from a stored
/// offset; a file whose first line is not a user conversation is remembered and never reopened.
@MainActor
final class CodexTranscriptWatcher {
    /// How often to look for new records. Transcripts are appended as the agent works.
    static let pollInterval: TimeInterval = 2
    /// Only files touched this recently are considered, which keeps each scan to a few files.
    static let lookback: TimeInterval = 30 * 60
    /// Most bytes read from one file in one pass.
    static let readChunk = 1 << 20
    /// On first sight of a large, long-running VS Code thread, read its head for metadata and
    /// its recent tail for the current turn. Replaying a 50–200 MB transcript from byte zero can
    /// leave Reef showing an hours-old "Done" state while Codex is visibly working.
    static let initialTailRead = 32 << 20

    private struct Entry {
        var offset: UInt64 = 0
        var session: TranscriptSession?
        /// Set once a file is known not to be a user conversation, so it is skipped from then on.
        var ignored = false
    }

    private let root: URL
    private let onSession: (TranscriptSession) -> Void
    private var entries: [String: Entry] = [:]
    private var timer: Timer?

    init(root: URL, onSession: @escaping (TranscriptSession) -> Void) {
        self.root = root
        self.onSession = onSession
    }

    func start() {
        guard timer == nil else { return }
        scanOnce()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scanOnce() }
        }
        Log.info("codex", "watching transcripts", ["root": root.path])
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        entries.removeAll()
    }

    func scanOnce() {
        for (url, modified) in recentTranscripts() {
            var entry = entries[url.path] ?? Entry()
            guard !entry.ignored else { continue }

            if entry.offset == 0, entry.session == nil {
                switch seedEntry(at: url) {
                case let .ready(session, offset):
                    entry.session = session
                    entry.offset = offset
                    var current = session
                    current.lastActivityAt = max(current.lastActivityAt, modified)
                    entry.session = current
                    entries[url.path] = entry
                    onSession(current)
                case .ignored:
                    entry.ignored = true
                    entries[url.path] = entry
                    Log.info("codex", "ignoring transcript", ["file": url.lastPathComponent])
                case .retry:
                    break
                }
                continue
            }

            guard let (lines, newOffset) = readNewLines(at: url, from: entry.offset) else {
                // Rotated or truncated under us: the session we folded no longer matches the file.
                entries[url.path] = Entry()
                continue
            }
            entry.offset = newOffset
            var changed = false

            for line in lines {
                if entry.session == nil {
                    guard let begun = CodexTranscript.begin(metaLine: line) else {
                        // The first complete line settles it: a subagent transcript, or a shape
                        // Reef does not understand. Either way, stop looking at this file.
                        entry.ignored = true
                        Log.info("codex", "ignoring transcript", ["file": url.lastPathComponent])
                        break
                    }
                    entry.session = begun
                    changed = true
                    continue
                }
                CodexTranscript.fold(&entry.session!, line)
                changed = true
            }

            // The file's own clock is what says this session is alive. Record timestamps can be
            // older than the file (a transcript copied or touched, or records Reef cannot date),
            // and a session that looks ancient is pruned as idle and then found again on the
            // next pass, flickering on and off the island.
            if var session = entry.session {
                session.lastActivityAt = max(session.lastActivityAt, modified)
                entry.session = session
            }
            entries[url.path] = entry
            if changed, let session = entry.session { onSession(session) }
        }
    }

    private enum SeedResult {
        case ready(TranscriptSession, UInt64)
        case ignored
        case retry
    }

    /// Builds a current snapshot without replaying an unbounded transcript. The first chunk
    /// supplies `session_meta`; for a large file the latest 32 MB supplies the newest lifecycle
    /// record (`task_started`, `task_complete`, or `turn_aborted`) and assistant output. Future
    /// polls resume at the last complete newline near EOF.
    private func seedEntry(at url: URL) -> SeedResult {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .retry }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd(), end > 0,
              (try? handle.seek(toOffset: 0)) != nil,
              let head = try? handle.read(upToCount: Self.readChunk), !head.isEmpty
        else { return .retry }

        let (headLines, headConsumed) = CodexTranscript.completeLines(in: head)
        guard let meta = headLines.first else { return .retry }
        guard var session = CodexTranscript.begin(metaLine: meta) else { return .ignored }
        for line in headLines.dropFirst() { CodexTranscript.fold(&session, line) }

        var offset = UInt64(headConsumed)
        guard end > offset else { return .ready(session, offset) }

        // Small files continue directly after the head. Large files jump to a bounded recent
        // window; its first fragment may begin mid-record and is harmlessly ignored by `fold`.
        let tailCapacity = UInt64(Self.initialTailRead)
        let tailStart = end > tailCapacity ? max(offset, end - tailCapacity) : offset
        guard (try? handle.seek(toOffset: tailStart)) != nil,
              let tail = try? handle.read(upToCount: Int(end - tailStart)), !tail.isEmpty
        else { return .ready(session, offset) }
        let (tailLines, tailConsumed) = CodexTranscript.completeLines(in: tail)
        for line in tailLines { CodexTranscript.fold(&session, line) }

        // If the only recent record is larger than the bounded window, skip that partial record
        // rather than getting permanently stuck rereading the same bytes. The next complete
        // append will be processed normally.
        offset = tailConsumed > 0 ? tailStart + UInt64(tailConsumed) : end
        return .ready(session, offset)
    }

    /// Transcript files under the date folders with their modification dates, newest first,
    /// touched within the lookback.
    private func recentTranscripts() -> [(URL, Date)] {
        let cutoff = Date().addingTimeInterval(-Self.lookback)
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        var found: [(URL, Date)] = []
        for case let url as URL in walker where url.lastPathComponent.hasPrefix("rollout-") && url.pathExtension == "jsonl" {
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modified > cutoff else { continue }
            found.append((url, modified))
        }
        return found.sorted { $0.1 > $1.1 }
    }

    /// Complete lines appended since `offset`, at most `readChunk` bytes of them. Transcripts on
    /// this machine reach hundreds of megabytes, and offsets do not survive a relaunch, so an
    /// unbounded read would stall the main actor on the first sighting of a long session. A file
    /// larger than one chunk catches up over successive polls.
    private func readNewLines(at url: URL, from offset: UInt64) -> ([Data], UInt64)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        if end < offset { return nil }              // truncated or rotated: forget what we had
        guard end > offset else { return ([], offset) }
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.read(upToCount: Self.readChunk), !data.isEmpty
        else { return ([], offset) }
        let (lines, consumed) = CodexTranscript.completeLines(in: data)
        // A single record longer than a chunk would otherwise stall this file forever.
        guard consumed > 0 else { return ([], offset + UInt64(data.count)) }
        return (lines, offset + UInt64(consumed))
    }
}
