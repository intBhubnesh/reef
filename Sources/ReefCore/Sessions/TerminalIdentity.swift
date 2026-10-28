import Foundation

/// Where a session's agent process lives, captured by the bridge from its environment.
public struct TerminalIdentity: Codable, Equatable {
    public var tty: String?
    public var bundleID: String?
    public var termProgram: String?
    public var kittyWindowID: Int?
    public var kittyPID: Int?
    public var kittyListenOn: String?
    public var tmuxPane: String?
    public var vscodePID: Int?
    public var pid: Int?
    public var ppid: Int?
    public var ghosttyMarker: String?

    public init(tty: String? = nil, bundleID: String? = nil, termProgram: String? = nil, kittyWindowID: Int? = nil,
                kittyPID: Int? = nil, kittyListenOn: String? = nil, tmuxPane: String? = nil, vscodePID: Int? = nil,
                pid: Int? = nil, ppid: Int? = nil, ghosttyMarker: String? = nil) {
        self.tty = tty; self.bundleID = bundleID; self.termProgram = termProgram; self.kittyWindowID = kittyWindowID
        self.kittyPID = kittyPID; self.kittyListenOn = kittyListenOn; self.tmuxPane = tmuxPane; self.vscodePID = vscodePID
        self.pid = pid; self.ppid = ppid; self.ghosttyMarker = ghosttyMarker
    }

    /// No terminal and no host app: `claude -p`, SDK runs, probes.
    public var isHeadless: Bool { tty == nil && bundleID == nil }

    /// Reads the `reef` object the bridge adds to every event.
    public static func from(raw: [String: Any]) -> TerminalIdentity {
        guard let reef = raw["reef"] as? [String: Any] else { return TerminalIdentity() }
        let env = reef["env"] as? [String: String] ?? [:]
        func int(_ key: String) -> Int? { env[key].flatMap(Int.init) }
        return TerminalIdentity(
            tty: reef["tty"] as? String,
            bundleID: env["__CFBundleIdentifier"],
            termProgram: env["TERM_PROGRAM"],
            kittyWindowID: int("KITTY_WINDOW_ID"),
            kittyPID: int("KITTY_PID"),
            kittyListenOn: env["KITTY_LISTEN_ON"],
            tmuxPane: env["TMUX_PANE"],
            vscodePID: int("VSCODE_PID"),
            pid: reef["pid"] as? Int,
            ppid: reef["ppid"] as? Int,
            ghosttyMarker: reef["title_marker"] as? String
        )
    }
}
