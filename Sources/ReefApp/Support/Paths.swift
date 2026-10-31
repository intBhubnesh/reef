import Foundation

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let reefDir = home.appendingPathComponent(".reef")
    static let binDir = reefDir.appendingPathComponent("bin")
    static let runDir = reefDir.appendingPathComponent("run")
    static let cacheDir = reefDir.appendingPathComponent("cache")
    static let socketPath = runDir.appendingPathComponent("reef.sock").path
    static let bridgeBinary = binDir.appendingPathComponent("reef-bridge")
    static let supportDir = home.appendingPathComponent("Library/Application Support/Reef")
    static let settingsFile = supportDir.appendingPathComponent("settings.json")
    static let sessionTerminalsFile = supportDir.appendingPathComponent("session-terminals.json")
    static let logDir = home.appendingPathComponent("Library/Logs/Reef")
    static let logFile = logDir.appendingPathComponent("reef.log")
    static let claudeSettings = home.appendingPathComponent(".claude/settings.json").path
    static let codexHooks = home.appendingPathComponent(".codex/hooks.json").path
    static let codexConfig = home.appendingPathComponent(".codex/config.toml").path
    /// Where Codex writes a transcript per session, whatever front end it runs in.
    static let codexSessions = home.appendingPathComponent(".codex/sessions")

    static func ensureDirectories() {
        for dir in [binDir, runDir, cacheDir, supportDir, logDir] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
