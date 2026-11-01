import Foundation

/// Adds Reef's own context (`source` and a `reef` object) to a raw hook event before it crosses the socket.
public enum Enricher {
    public static let envKeys = [
        "TERM_PROGRAM", "TERM_SESSION_ID", "ITERM_SESSION_ID", "KITTY_WINDOW_ID", "KITTY_PID", "KITTY_LISTEN_ON",
        "GHOSTTY_RESOURCES_DIR", "TMUX", "TMUX_PANE", "VSCODE_PID", "__CFBundleIdentifier",
        "WEZTERM_PANE",
    ]

    public static func enrich(event raw: [String: Any], source: AgentSource, env: [String: String], tty: String?,
                              pid: Int, ppid: Int, git: GitInfo?, titleMarker: String?) -> [String: Any] {
        var out = raw
        out["source"] = source.rawValue
        var reef: [String: Any] = ["pid": pid, "ppid": ppid, "env": env.filter { envKeys.contains($0.key) }]
        if let tty { reef["tty"] = tty }
        if let git {
            var g = ["root": git.root]
            if let branch = git.branch { g["branch"] = branch }
            reef["git"] = g
        }
        if let titleMarker { reef["title_marker"] = titleMarker }
        out["reef"] = reef
        return out
    }
}

/// The terminal-title marker the jump engine searches for (Ghostty has no remote control).
public enum TitleMarker {
    public static func marker(sessionID: String) -> String {
        "reef:" + String(sessionID.prefix(8))
    }

    /// `ESC ] 2 ; <project> · <marker> BEL`
    public static func oscTitle(project: String?, marker: String) -> Data {
        let title = project.map { "\($0) · \(marker)" } ?? marker
        var data = Data([0x1b])
        data.append("]2;\(title)".data(using: .utf8)!)
        data.append(0x07)
        return data
    }
}
