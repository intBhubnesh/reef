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
    public var soundStarted = true
    public var soundActionCompleted = true
    public var soundInputNeeded = true
    public var soundDone = true
    public var soundFailed = true
    public var notifyAllFinished = false
    public var barkEnabled = false
    public var barkServerURL = "https://api.day.app"
    public var barkNotifyInputNeeded = true
    public var barkNotifyDone = true
    public var barkNotifyFailed = true
    public var barkLevel = BarkNotificationLevel.active.rawValue
    /// Empty uses the Bark server/app default sound.
    public var barkSound = ""
    public var panelMaxWidth: Double = 648
    public var panelMaxHeight: Double = 580
    /// "automatic" or a stable CoreGraphics display UUID. A disconnected display remains the
    /// stored preference and is selected again when it returns.
    public var preferredDisplayID = "automatic"
    public var showProject = true
    public var showBranch = true
    public var showSubagents = true
    public var showHeadless = false
    /// Watch `~/.codex/sessions` so Codex front ends that do not run hooks, such as the VS Code
    /// extension, still appear. Those sessions are read-only.
    public var watchCodexTranscripts = true
    public var hooksInstalledByUser: [String] = []
    public var hookIntentBySource: [String: String] = [:]
    /// User-selectable status → Bloub emotion mapping. Invalid or missing entries fall back to
    /// `AvatarStatusSlot.defaultEmotion` at the point of use.
    public var avatarEmotionByStatus = AvatarStatusSlot.defaultMapping
    /// Reef's orb or an open-bot-avatar catalogue id. Unknown ids resolve to the orb at render time.
    public var avatarDesignID = AvatarDesign.orb.id

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
        soundStarted = try c.decodeIfPresent(Bool.self, forKey: .soundStarted) ?? d.soundStarted
        soundActionCompleted = try c.decodeIfPresent(Bool.self, forKey: .soundActionCompleted) ?? d.soundActionCompleted
        soundInputNeeded = try c.decodeIfPresent(Bool.self, forKey: .soundInputNeeded) ?? d.soundInputNeeded
        soundDone = try c.decodeIfPresent(Bool.self, forKey: .soundDone) ?? d.soundDone
        soundFailed = try c.decodeIfPresent(Bool.self, forKey: .soundFailed) ?? d.soundFailed
        notifyAllFinished = try c.decodeIfPresent(Bool.self, forKey: .notifyAllFinished) ?? d.notifyAllFinished
        barkEnabled = try c.decodeIfPresent(Bool.self, forKey: .barkEnabled) ?? d.barkEnabled
        barkServerURL = try c.decodeIfPresent(String.self, forKey: .barkServerURL) ?? d.barkServerURL
        barkNotifyInputNeeded = try c.decodeIfPresent(Bool.self, forKey: .barkNotifyInputNeeded) ?? d.barkNotifyInputNeeded
        barkNotifyDone = try c.decodeIfPresent(Bool.self, forKey: .barkNotifyDone) ?? d.barkNotifyDone
        barkNotifyFailed = try c.decodeIfPresent(Bool.self, forKey: .barkNotifyFailed) ?? d.barkNotifyFailed
        barkLevel = try c.decodeIfPresent(String.self, forKey: .barkLevel) ?? d.barkLevel
        barkSound = try c.decodeIfPresent(String.self, forKey: .barkSound) ?? d.barkSound
        panelMaxWidth = try c.decodeIfPresent(Double.self, forKey: .panelMaxWidth) ?? d.panelMaxWidth
        panelMaxHeight = try c.decodeIfPresent(Double.self, forKey: .panelMaxHeight) ?? d.panelMaxHeight
        preferredDisplayID = try c.decodeIfPresent(String.self, forKey: .preferredDisplayID) ?? d.preferredDisplayID
        showProject = try c.decodeIfPresent(Bool.self, forKey: .showProject) ?? d.showProject
        showBranch = try c.decodeIfPresent(Bool.self, forKey: .showBranch) ?? d.showBranch
        showSubagents = try c.decodeIfPresent(Bool.self, forKey: .showSubagents) ?? d.showSubagents
        showHeadless = try c.decodeIfPresent(Bool.self, forKey: .showHeadless) ?? d.showHeadless
        watchCodexTranscripts = try c.decodeIfPresent(Bool.self, forKey: .watchCodexTranscripts) ?? d.watchCodexTranscripts
        hooksInstalledByUser = try c.decodeIfPresent([String].self, forKey: .hooksInstalledByUser) ?? d.hooksInstalledByUser
        hookIntentBySource = try c.decodeIfPresent([String: String].self, forKey: .hookIntentBySource) ?? d.hookIntentBySource
        if hookIntentBySource.isEmpty {
            for source in hooksInstalledByUser { hookIntentBySource[source] = HookIntent.installed.rawValue }
        }
        avatarEmotionByStatus = try c.decodeIfPresent([String: String].self, forKey: .avatarEmotionByStatus)
            ?? d.avatarEmotionByStatus
        avatarDesignID = try c.decodeIfPresent(String.self, forKey: .avatarDesignID) ?? d.avatarDesignID
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
        case .started: return soundStarted
        case .actionCompleted: return soundActionCompleted
        case .inputNeeded: return soundInputNeeded
        case .done: return soundDone
        case .failed: return soundFailed
        }
    }

    public func barkEnabled(_ kind: SoundKind) -> Bool {
        guard barkEnabled else { return false }
        switch kind {
        case .started, .actionCompleted: return false
        case .inputNeeded: return barkNotifyInputNeeded
        case .done: return barkNotifyDone
        case .failed: return barkNotifyFailed
        }
    }

    public var barkNotificationLevel: BarkNotificationLevel {
        BarkNotificationLevel(rawValue: barkLevel) ?? .active
    }

    public func hookIntent(for source: AgentSource) -> HookIntent {
        hookIntentBySource[source.rawValue].flatMap(HookIntent.init(rawValue:)) ?? .untouched
    }
}
