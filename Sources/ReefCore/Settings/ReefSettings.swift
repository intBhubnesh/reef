import Foundation

/// User preferences, stored as JSON. Missing or unknown keys fall back to defaults.
public struct ReefSettings: Codable, Equatable {
    public var launchAtLogin = false
    public var hoverExpand = true
    public var hoverDelay: Double = 0.15
    public var autoCollapseOnLeave = true
    public var revealDwell: Double = 5
    public var idleCleanupHours: Double = 2
    public var muted = false
    public var soundInputNeeded = true
    public var soundDone = true
    public var soundFailed = true
    public var notifyAllFinished = false
    public var panelMaxWidth: Double = 648
    public var panelMaxHeight: Double = 580
    public var showProject = true
    public var showBranch = true
    public var showSubagents = true
    public var showHeadless = false
    /// Watch `~/.codex/sessions` so Codex front ends that do not run hooks, such as the VS Code
    /// extension, still appear. Those sessions are read-only.
    public var watchCodexTranscripts = true
    public var hooksInstalledByUser: [String] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReefSettings()
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        hoverExpand = try c.decodeIfPresent(Bool.self, forKey: .hoverExpand) ?? d.hoverExpand
        hoverDelay = try c.decodeIfPresent(Double.self, forKey: .hoverDelay) ?? d.hoverDelay
        autoCollapseOnLeave = try c.decodeIfPresent(Bool.self, forKey: .autoCollapseOnLeave) ?? d.autoCollapseOnLeave
        revealDwell = try c.decodeIfPresent(Double.self, forKey: .revealDwell) ?? d.revealDwell
        idleCleanupHours = try c.decodeIfPresent(Double.self, forKey: .idleCleanupHours) ?? d.idleCleanupHours
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? d.muted
        soundInputNeeded = try c.decodeIfPresent(Bool.self, forKey: .soundInputNeeded) ?? d.soundInputNeeded
        soundDone = try c.decodeIfPresent(Bool.self, forKey: .soundDone) ?? d.soundDone
        soundFailed = try c.decodeIfPresent(Bool.self, forKey: .soundFailed) ?? d.soundFailed
        notifyAllFinished = try c.decodeIfPresent(Bool.self, forKey: .notifyAllFinished) ?? d.notifyAllFinished
        panelMaxWidth = try c.decodeIfPresent(Double.self, forKey: .panelMaxWidth) ?? d.panelMaxWidth
        panelMaxHeight = try c.decodeIfPresent(Double.self, forKey: .panelMaxHeight) ?? d.panelMaxHeight
        showProject = try c.decodeIfPresent(Bool.self, forKey: .showProject) ?? d.showProject
        showBranch = try c.decodeIfPresent(Bool.self, forKey: .showBranch) ?? d.showBranch
        showSubagents = try c.decodeIfPresent(Bool.self, forKey: .showSubagents) ?? d.showSubagents
        showHeadless = try c.decodeIfPresent(Bool.self, forKey: .showHeadless) ?? d.showHeadless
        watchCodexTranscripts = try c.decodeIfPresent(Bool.self, forKey: .watchCodexTranscripts) ?? d.watchCodexTranscripts
        hooksInstalledByUser = try c.decodeIfPresent([String].self, forKey: .hooksInstalledByUser) ?? d.hooksInstalledByUser
    }

    public static func load(from url: URL) -> ReefSettings {
        guard let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(ReefSettings.self, from: data) else {
            return ReefSettings()
        }
        return decoded
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    public var notchTiming: NotchTiming {
        var t = NotchTiming()
        t.hoverDelay = hoverDelay
        t.revealDwell = revealDwell
        t.autoCollapseOnLeave = autoCollapseOnLeave
        return t
    }

    public func soundEnabled(_ kind: SoundKind) -> Bool {
        guard !muted else { return false }
        switch kind {
        case .inputNeeded: return soundInputNeeded
        case .done: return soundDone
        case .failed: return soundFailed
        }
    }
}
