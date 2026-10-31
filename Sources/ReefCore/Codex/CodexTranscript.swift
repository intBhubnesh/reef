import Foundation

/// A Codex session reconstructed from the transcript it writes to disk, for front ends that do
/// not run hooks. Read-only: a transcript records what happened, it cannot answer an approval.
public struct TranscriptSession: Equatable {
    public let id: String
    public let cwd: String?
    /// Which front end wrote it: `codex_vscode`, `codex-tui`, and so on.
    public let originator: String?
    public var model: String?
    public var isWorking: Bool
    public var lastAssistantMessage: String?
    public let startedAt: Date
    public var lastActivityAt: Date
    public var turnCount: Int

    public init(id: String, cwd: String?, originator: String?, model: String?, isWorking: Bool,
                lastAssistantMessage: String?, startedAt: Date, lastActivityAt: Date, turnCount: Int) {
        self.id = id
        self.cwd = cwd
        self.originator = originator
        self.model = model
        self.isWorking = isWorking
        self.lastAssistantMessage = lastAssistantMessage
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.turnCount = turnCount
    }
}

/// Folds `~/.codex/sessions/**/rollout-*.jsonl` records into a session.
///
/// The first line is `session_meta`; later lines are typed records. Only real conversations are
/// surfaced: Codex writes a transcript per internal review subagent too, and those would bury
/// the user's actual work.
public enum CodexTranscript {
    /// Front ends that deliver Reef's hooks themselves. Reading their transcripts would show the
    /// session twice, and would bring it back after its `SessionEnd` removed it.
    static let hookedOriginators: Set<String> = ["codex-tui", "codex_cli", "codex_exec"]

    /// Reads the transcript's first line. Returns nil for anything that is not a user
    /// conversation, including partial lines written while Codex is still appending.
    public static func begin(metaLine: Data) -> TranscriptSession? {
        guard let record = object(metaLine),
              record["type"] as? String == "session_meta",
              let payload = record["payload"] as? [String: Any],
              let id = payload["id"] as? String, !id.isEmpty,
              payload["thread_source"] as? String == "user",
              payload["parent_thread_id"] == nil || payload["parent_thread_id"] is NSNull,
              !hookedOriginators.contains(payload["originator"] as? String ?? "")
        else { return nil }
        let started = timestamp(record) ?? Date()
        return TranscriptSession(id: id,
                                 cwd: payload["cwd"] as? String,
                                 originator: payload["originator"] as? String,
                                 model: nil,
                                 isWorking: false,
                                 lastAssistantMessage: nil,
                                 startedAt: started,
                                 lastActivityAt: started,
                                 turnCount: 0)
    }

    /// Applies one record. Unknown or unparseable lines are ignored, so a Codex update that adds
    /// record types degrades to missing detail rather than a broken session.
    public static func fold(_ session: inout TranscriptSession, _ line: Data) {
        guard let record = object(line) else { return }
        if let at = timestamp(record), at > session.lastActivityAt { session.lastActivityAt = at }
        guard let payload = record["payload"] as? [String: Any] else { return }

        switch record["type"] as? String {
        case "event_msg":
            switch payload["type"] as? String {
            case "task_started":
                session.isWorking = true
                session.turnCount += 1
            case "task_complete", "turn_aborted":
                // turn_aborted is what Stop in the editor writes, and no task_complete follows
                // it. Without this the card claims to be working until the idle sweep.
                session.isWorking = false
            case "thread_settings_applied":
                if let settings = payload["thread_settings"] as? [String: Any],
                   let model = settings["model"] as? String, !model.isEmpty {
                    session.model = model
                }
            default:
                break
            }
        case "response_item":
            guard payload["type"] as? String == "message",
                  payload["role"] as? String == "assistant" else { return }
            let text = (payload["content"] as? [[String: Any]] ?? [])
                .compactMap { $0["text"] as? String }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { session.lastAssistantMessage = text }
        default:
            break
        }
    }

    /// Splits appended bytes into whole records, leaving a trailing partial line unconsumed, and
    /// reports how many bytes were used so the caller can resume after them. A transcript is read
    /// while Codex is still writing to it, so the last line is often half a record.
    public static func completeLines(in data: Data) -> (lines: [Data], consumed: Int) {
        let newline = UInt8(ascii: "\n")
        guard let lastBreak = data.lastIndex(of: newline) else { return ([], 0) }
        let complete = data[..<lastBreak]
        let lines = complete.split(separator: newline).map { Data($0) }
        return (lines, data.distance(from: data.startIndex, to: lastBreak) + 1)
    }

    private static func object(_ line: Data) -> [String: Any]? {
        guard !line.isEmpty, let parsed = try? JSONSerialization.jsonObject(with: line) else { return nil }
        return parsed as? [String: Any]
    }

    private static let formatters: [ISO8601DateFormatter] = {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [withFraction, ISO8601DateFormatter()]
    }()

    private static func timestamp(_ record: [String: Any]) -> Date? {
        guard let raw = record["timestamp"] as? String else { return nil }
        for formatter in formatters {
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }
}
