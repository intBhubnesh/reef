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
    public let capturedAt: Date

    public init(fiveHour: UsageWindow?, sevenDay: UsageWindow?, capturedAt: Date) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.capturedAt = capturedAt
    }

    /// Past this age the numbers are shown greyed rather than as live values.
    public func isStale(now: Date = Date(), maxAge: TimeInterval = 600) -> Bool {
        now.timeIntervalSince(capturedAt) > maxAge
    }

    /// Reads the cache the status-line shim writes. Returns nil for anything unrecognisable,
    /// so a malformed or truncated file simply means "no usage data" rather than a crash.
    public static func parse(_ data: Data, now: Date) -> UsageSnapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: data), var json = object as? [String: Any] else {
            return nil
        }
        if let wrapped = json["rate_limits"] as? [String: Any] { json = wrapped }
        let five = window(json["five_hour"])
        let seven = window(json["seven_day"])
        guard five != nil || seven != nil else { return nil }
        return UsageSnapshot(fiveHour: five, sevenDay: seven, capturedAt: now)
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
