import Foundation

/// kitty remote control (`kitten @ focus-window`); needs `allow_remote_control yes` in kitty.conf.
enum KittyRemote {
    static var kittenPath: String? {
        Shell.which("kitten", extra: ["/Applications/kitty.app/Contents/MacOS/kitten"])
    }

    /// Ids of kitty windows that currently have focus (one per OS window), or nil when kitty cannot be asked.
    /// Synchronous with a short timeout; used on app-activation events only.
    static func focusedWindowIDs(listenOn: String?) -> Set<Int>? {
        guard let kitten = kittenPath else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: kitten)
        var args = ["@"]
        if let listenOn { args += ["--to", listenOn] }
        process.arguments = args + ["ls"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(0.3)
        while process.isRunning, Date() < deadline { usleep(5_000) }
        if process.isRunning { process.terminate(); return nil }
        guard process.terminationStatus == 0,
              let json = try? JSONSerialization.jsonObject(with: pipe.fileHandleForReading.readDataToEndOfFile()) as? [[String: Any]]
        else { return nil }
        var focused = Set<Int>()
        for osWindow in json where (osWindow["is_focused"] as? Bool) == true {
            for tab in osWindow["tabs"] as? [[String: Any]] ?? [] {
                for window in tab["windows"] as? [[String: Any]] ?? [] where (window["is_focused"] as? Bool) == true {
                    if let id = window["id"] as? Int { focused.insert(id) }
                }
            }
        }
        return focused
    }

    static func focusWindow(id: Int, listenOn: String?) async -> Bool {
        guard let kitten = kittenPath else { return false }
        var args = ["@"]
        if let listenOn { args += ["--to", listenOn] }
        args += ["focus-window", "--match", "id:\(id)"]
        return await Shell.run(kitten, args) == 0
    }
}

enum TmuxFocus {
    static func select(pane: String) async -> Bool {
        guard let tmux = Shell.which("tmux") else { return false }
        let window = await Shell.run(tmux, ["select-window", "-t", pane])
        let selected = await Shell.run(tmux, ["select-pane", "-t", pane])
        return window == 0 || selected == 0
    }
}
