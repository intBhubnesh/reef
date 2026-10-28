import Foundation

/// kitty remote control (`kitten @ focus-window`); needs `allow_remote_control yes` in kitty.conf.
enum KittyRemote {
    static var kittenPath: String? {
        Shell.which("kitten", extra: ["/Applications/kitty.app/Contents/MacOS/kitten"])
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
