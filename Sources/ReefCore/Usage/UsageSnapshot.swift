import Foundation

/// One rate-limit window as the agent's status line reports it.
public struct UsageWindow: Equatable {
    public let usedPercent: Int
    public let resetsAt: Date?

    public init(usedPercent: Int, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    /// Time until the window resets, e.g. "3h9m". Nil when unknown or already past.
    public func remaining(now: Date = Date()) -> String? {
        guard let resetsAt else { return nil }
        let seconds = Int(resetsAt.timeIntervalSince(now))
        guard seconds > 0 else { return nil }
        let days = seconds / 86_400, hours = (seconds % 86_400) / 3600, minutes = (seconds % 3600) / 60
        if days > 0 { return hours > 0 ? "\(days)d\(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h\(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
    }
}

/// What Reef knows about the agent's limits, and when it learned it.
public struct UsageSnapshot: Equatable {
    public let fiveHour: UsageWindow?
    public let sevenDay: UsageWindow?
    /// Present behind a Claude apps gateway that sets a spend limit.
    public let spendLimit: UsageWindow?
    /// The agent's own name for the model it is running, e.g. "Opus".
    public let modelName: String?
    public let capturedAt: Date

    public init(fiveHour: UsageWindow?, sevenDay: UsageWindow?, spendLimit: UsageWindow? = nil,
                modelName: String? = nil, capturedAt: Date) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.spendLimit = spendLimit
        self.modelName = modelName
        self.capturedAt = capturedAt
    }

    /// What the right-hand header block shows: the running model and the limit it draws on.
    /// A spend limit is more specific than the weekly window, so it wins when present.
    public var modelWindow: UsageWindow? { spendLimit ?? sevenDay }

    /// Past this age the numbers are shown greyed rather than as live values.
    public func isStale(now: Date = Date(), maxAge: TimeInterval = 600) -> Bool {
        now.timeIntervalSince(capturedAt) > maxAge
    }

    /// Reads the cache the status-line shim writes. Returns nil for anything unrecognisable,
    /// so a malformed or truncated file simply means "no usage data" rather than a crash.
    public static func parse(_ data: Data, now: Date) -> UsageSnapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: data), let outer = object as? [String: Any] else {
            return nil
        }
        let model = (outer["model"] as? [String: Any])?["display_name"] as? String
        let json = (outer["rate_limits"] as? [String: Any]) ?? outer
        let five = window(json["five_hour"])
        let seven = window(json["seven_day"])
        let spend = window(json["spend_limit"])
        guard five != nil || seven != nil || spend != nil else { return nil }
        return UsageSnapshot(fiveHour: five, sevenDay: seven, spendLimit: spend, modelName: model, capturedAt: now)
    }

    /// Reads the `event_msg.token_count.rate_limits` record written to Codex rollout JSONL.
    /// Codex names its windows `primary` and `secondary`, so their duration—not their position—
    /// determines whether Reef presents them as the five-hour or seven-day allowance.
    public static func parseCodexEvent(_ data: Data) -> UsageSnapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let record = object as? [String: Any],
              record["type"] as? String == "event_msg",
              let payload = record["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let limits = payload["rate_limits"] as? [String: Any]
        else { return nil }

        var fiveHour: UsageWindow?
        var sevenDay: UsageWindow?
        for key in ["primary", "secondary", "individual_limit"] {
            guard let raw = limits[key] as? [String: Any],
                  let minutes = integer(raw["window_minutes"]),
                  let value = codexWindow(raw)
            else { continue }
            switch minutes {
            case 300: fiveHour = value
            case 10_080: sevenDay = value
            default: break
            }
        }
        guard fiveHour != nil || sevenDay != nil else { return nil }
        return UsageSnapshot(fiveHour: fiveHour, sevenDay: sevenDay,
                             modelName: nil, capturedAt: codexTimestamp(record) ?? Date())
    }

    /// Finds the newest complete Codex usage record in a transcript chunk. A chunk can begin in
    /// the middle of a JSONL record when the app reads only a bounded tail; that fragment simply
    /// fails parsing and the search continues.
    public static func latestCodexSnapshot(in data: Data) -> UsageSnapshot? {
        let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        for line in lines.reversed() {
            if let snapshot = parseCodexEvent(Data(line)) { return snapshot }
        }
        return nil
    }

    private static func window(_ value: Any?) -> UsageWindow? {
        guard let dict = value as? [String: Any] else { return nil }
        guard let percent = dict["used_percentage"] as? Int ?? (dict["used_percentage"] as? Double).map(Int.init) else {
            return nil
        }
        var resets: Date?
        if let iso = dict["resets_at"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            resets = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        } else if let epoch = dict["resets_at"] as? Double {
            resets = Date(timeIntervalSince1970: epoch)
        }
        return UsageWindow(usedPercent: percent, resetsAt: resets)
    }

    private static func codexWindow(_ raw: [String: Any]) -> UsageWindow? {
        guard let percent = integer(raw["used_percent"]) else { return nil }
        let resets = number(raw["resets_at"]).map { Date(timeIntervalSince1970: $0) }
        return UsageWindow(usedPercent: percent, resetsAt: resets)
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func codexTimestamp(_ record: [String: Any]) -> Date? {
        guard let raw = record["timestamp"] as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
}

/// Who owns Claude Code's single `statusLine` slot. Reef never takes a slot another app holds.
public enum StatusLineState: Equatable {
    case free
    case ownedByReef
    case ownedByOther(String)

    public static let reefMarker = "/.reef/bin/reef-statusline"

    public static func of(command: String?) -> StatusLineState {
        guard let command, !command.trimmingCharacters(in: .whitespaces).isEmpty else { return .free }
        return command.contains(reefMarker) ? .ownedByReef : .ownedByOther(command)
    }
}
