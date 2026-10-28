import Foundation
import ReefCore

/// App-side hook installation: copies the bridge into ~/.reef/bin and edits the agents' hook files.
enum HookInstaller {
    static func hookFile(_ source: AgentSource) -> String {
        source == .claude ? Paths.claudeSettings : Paths.codexHooks
    }

    /// The bridge shipped inside Reef.app, or the sibling debug build during development.
    static var bridgeSource: URL? {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/reef-bridge")
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        if let exe = Bundle.main.executableURL {
            let sibling = exe.deletingLastPathComponent().appendingPathComponent("reef-bridge")
            if FileManager.default.isExecutableFile(atPath: sibling.path) { return sibling }
        }
        return nil
    }

    static func installBridgeBinary() -> String? {
        guard let source = bridgeSource else { return "reef-bridge binary not found next to the app" }
        do {
            try FileManager.default.createDirectory(at: Paths.binDir, withIntermediateDirectories: true)
            let target = Paths.bridgeBinary
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: source, to: target)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
            return nil
        } catch {
            return "could not copy reef-bridge: \(error.localizedDescription)"
        }
    }

    @discardableResult
    static func install(_ source: AgentSource) -> String? {
        if let error = installBridgeBinary() { return error }
        let ok = HookFiles.transform(file: hookFile(source)) { HookConfig.install(into: $0, source: source) }
        Log.info("hook", ok ? "installed" : "install failed", ["source": source.rawValue])
        return ok ? nil : "could not write \(hookFile(source))"
    }

    @discardableResult
    static func uninstall(_ source: AgentSource) -> String? {
        let ok = HookFiles.transform(file: hookFile(source)) { HookConfig.uninstall(from: $0, source: source) }
        Log.info("hook", ok ? "uninstalled" : "uninstall failed", ["source": source.rawValue])
        return ok ? nil : "could not write \(hookFile(source))"
    }

    static func status(_ source: AgentSource) -> HookConfig.HookStatus {
        HookConfig.status(of: HookFiles.read(file: hookFile(source)) ?? [:], source: source)
    }

    static var terminalTitleEnvSet: Bool {
        ((HookFiles.read(file: Paths.claudeSettings)?["env"] as? [String: String])?[HookConfig.terminalTitleEnvKey]) == "1"
    }

    static func removeTerminalTitleEnv() {
        HookFiles.transform(file: Paths.claudeSettings) { root in
            var root = root
            var env = root["env"] as? [String: String] ?? [:]
            env[HookConfig.terminalTitleEnvKey] = nil
            root["env"] = env.isEmpty ? nil : env
            return root
        }
    }

    /// nil = Codex has no trust registry yet (cannot tell); true/false otherwise.
    static func codexTrusted() -> Bool? {
        guard let toml = try? String(contentsOfFile: Paths.codexConfig, encoding: .utf8),
              let root = HookFiles.read(file: Paths.codexHooks),
              let index = CodexTrust.ourEntryIndex(in: root, event: "PermissionRequest") else { return nil }
        return CodexTrust.isTrusted(hooksJSONPath: Paths.codexHooks, event: "PermissionRequest", entryIndex: index, configTOML: toml)
    }
}
