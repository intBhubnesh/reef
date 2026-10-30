import Foundation

/// The `reef-bridge` command: hook mode (stdin event → socket → stdout decision) plus install/uninstall/status.
public enum BridgeCLI {
    public static let waitTimeout: TimeInterval = 3600
    public static let fireTimeout: TimeInterval = 2

    public struct Paths {
        public let home: String
        public var reefDir: String { home + "/.reef" }
        public var socketPath: String { reefDir + "/run/reef.sock" }
        public var cacheDir: URL { URL(fileURLWithPath: reefDir + "/cache") }
        public var claudeSettings: String { home + "/.claude/settings.json" }
        public var codexHooks: String { home + "/.codex/hooks.json" }
        public init(home: String) { self.home = home }
    }

    public static func run(arguments: [String], stdin: Data, env: [String: String], stdout: (Data) -> Void) -> Int32 {
        let paths = Paths(home: env["HOME"] ?? NSHomeDirectory())
        // Status-line mode: Claude Code pipes its status payload in, Reef keeps the rate limits
        // and echoes the input back untouched so the user's status line still renders.
        if let index = arguments.firstIndex(of: "--task"), index + 1 < arguments.count,
           arguments[index + 1] == "statusline-cache" {
            statusLineCache(arguments: arguments, stdin: stdin, paths: paths, stdout: stdout)
            return 0
        }
        let subcommand = arguments.first.flatMap { $0.hasPrefix("--") ? nil : $0 }
        switch subcommand {
        case "install", "uninstall", "status":
            let source = sourceArgument(arguments)
            stdout(HookFiles.run(subcommand!, source: source, paths: paths).data(using: .utf8)!)
            return 0
        default:
            hook(arguments: arguments, stdin: stdin, env: env, paths: paths, stdout: stdout)
            return 0
        }
    }

    static func sourceArgument(_ arguments: [String]) -> AgentSource? {
        guard let index = arguments.firstIndex(of: "--source"), index + 1 < arguments.count else { return nil }
        return AgentSource(rawValue: arguments[index + 1])
    }

    private static func hook(arguments: [String], stdin: Data, env: [String: String], paths: Paths, stdout: (Data) -> Void) {
        let empty = "{}\n".data(using: .utf8)!
        guard let source = sourceArgument(arguments), let event = try? HookEvent.parse(source: source, data: stdin) else {
            stdout(empty); return
        }
        let tty = currentTTY()
        let marker = TitleMarker.marker(sessionID: event.sessionID)
        let git = event.cwd.flatMap { GitInfo.lookup(cwd: $0, cacheDir: paths.cacheDir) }
        let enriched = Enricher.enrich(event: event.raw, source: source, env: env, tty: tty,
                                       pid: Int(ProcessInfo.processInfo.processIdentifier), ppid: Int(getppid()),
                                       git: git, titleMarker: tty == nil ? nil : marker)
        if let tty, event.name == "SessionStart" || event.name == "UserPromptSubmit" {
            let project = git.map { URL(fileURLWithPath: $0.root).lastPathComponent }
                ?? event.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
            writeTitle(TitleMarker.oscTitle(project: project, marker: marker), to: tty)
        }
        let mode = BridgeMode.forEvent(name: event.name)
        let request = BridgeRequest(mode: mode, event: enriched)
        guard let line = try? request.encodedLine() else { stdout(empty); return }
        let client = UnixSocketClient(path: paths.socketPath)
        defer { client.close() }
        guard let replyLine = try? client.send(line, awaitReply: mode == .wait, timeout: mode == .wait ? waitTimeout : fireTimeout),
              let response = try? BridgeResponse.decode(line: replyLine),
              let data = try? JSONSerialization.data(withJSONObject: response.reply, options: [.sortedKeys])
        else { stdout(empty); return }
        stdout(data + "\n".data(using: .utf8)!)
    }

    /// Extracts `rate_limits` from the status-line payload into the cache the app polls.
    /// Prints nothing: Claude Code renders this command's stdout as the user's status line, and
    /// echoing the payload back would print raw session JSON under every prompt.
    static func statusLineCache(arguments: [String], stdin: Data, paths: Paths, stdout: (Data) -> Void) {
        let cachePath: String
        if let index = arguments.firstIndex(of: "--cache-file"), index + 1 < arguments.count {
            cachePath = arguments[index + 1]
        } else {
            cachePath = paths.reefDir + "/cache/rl.json"
        }
        guard let object = try? JSONSerialization.jsonObject(with: stdin), let json = object as? [String: Any],
              let limits = json["rate_limits"], JSONSerialization.isValidJSONObject(limits),
              let data = try? JSONSerialization.data(withJSONObject: limits)
        else { return }
        try? FileManager.default.createDirectory(atPath: (cachePath as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: cachePath), options: .atomic)
    }

    /// The controlling terminal of the hook process, if any.
    static func currentTTY() -> String? {
        for fd: Int32 in [0, 1, 2] {
            if isatty(fd) == 1, let name = ttyname(fd) { return String(cString: name) }
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-o", "tty=", "-p", String(getppid())]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let out = (String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty, out != "??", out != "-" else { return nil }
        return out.hasPrefix("/dev/") ? out : "/dev/" + out
    }

    static func writeTitle(_ data: Data, to tty: String) {
        let fd = open(tty, O_WRONLY | O_NONBLOCK)
        guard fd >= 0 else { return }
        data.withUnsafeBytes { _ = write(fd, $0.baseAddress, $0.count) }
        close(fd)
    }
}

/// File-level install/uninstall/status over `HookConfig`, with timestamped backups.
public enum HookFiles {
    public static func run(_ command: String, source: AgentSource?, paths: BridgeCLI.Paths) -> String {
        let sources = source.map { [$0] } ?? AgentSource.allCases
        return sources.map { src -> String in
            let file = src == .claude ? paths.claudeSettings : paths.codexHooks
            switch command {
            case "install":
                return transform(file: file) { HookConfig.install(into: $0, source: src) }
                    ? "\(src.rawValue): installed in \(file)\n" : "\(src.rawValue): failed to write \(file)\n"
            case "uninstall":
                return transform(file: file) { HookConfig.uninstall(from: $0, source: src) }
                    ? "\(src.rawValue): removed from \(file)\n" : "\(src.rawValue): failed to write \(file)\n"
            default:
                let status = HookConfig.status(of: read(file: file) ?? [:], source: src)
                return "\(src.rawValue): \(status.isComplete ? "installed" : "missing \(status.missingEvents.joined(separator: ","))")\n"
            }
        }.joined()
    }

    public static func read(file: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: file) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Applies `change` to the JSON file. An absent file starts from `{}`; a file that exists but cannot be
    /// parsed is left untouched (returns false) so a broken or half-written settings file is never replaced.
    /// Writes atomically, keeps the original POSIX mode, and leaves a timestamped backup.
    @discardableResult
    public static func transform(file: String, _ change: ([String: Any]) -> [String: Any]) -> Bool {
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: file)
        var existing: [String: Any] = [:]
        var mode: Int?
        if exists {
            guard let parsed = read(file: file) else { return false }
            existing = parsed
            mode = (try? fm.attributesOfItem(atPath: file))?[.posixPermissions] as? Int
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try? fm.copyItem(atPath: file, toPath: "\(file).backup.\(stamp)")
        }
        let updated = change(existing)
        guard let data = try? JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys]) else { return false }
        try? fm.createDirectory(atPath: (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        do {
            try data.write(to: URL(fileURLWithPath: file), options: .atomic)
            if let mode { try? fm.setAttributes([.posixPermissions: mode], ofItemAtPath: file) }
            return true
        } catch {
            return false
        }
    }
}
