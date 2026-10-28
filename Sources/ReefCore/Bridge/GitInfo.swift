import CryptoKit
import Foundation

/// Repository root and branch for a working directory, via `git`, cached briefly by path.
public struct GitInfo: Equatable, Codable {
    public let root: String
    public let branch: String?

    public init(root: String, branch: String?) { self.root = root; self.branch = branch }

    private struct CacheEntry: Codable { let info: GitInfo?; let at: Date }
    static let cacheTTL: TimeInterval = 60
    static let processTimeout: TimeInterval = 0.5

    public static func lookup(cwd: String, cacheDir: URL?) -> GitInfo? {
        let cacheURL = cacheDir?.appendingPathComponent("git-\(sha256(cwd)).json")
        if let cacheURL, let data = try? Data(contentsOf: cacheURL),
           let entry = try? JSONDecoder().decode(CacheEntry.self, from: data),
           Date().timeIntervalSince(entry.at) < cacheTTL {
            return entry.info
        }
        let info = run(cwd: cwd)
        if let cacheURL, let data = try? JSONEncoder().encode(CacheEntry(info: info, at: Date())) {
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cacheURL)
        }
        return info
    }

    private static func run(cwd: String) -> GitInfo? {
        guard FileManager.default.fileExists(atPath: cwd) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", cwd, "rev-parse", "--show-toplevel", "--abbrev-ref", "HEAD"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(processTimeout)
        while process.isRunning, Date() < deadline { usleep(5_000) }
        if process.isRunning { process.terminate(); return nil }
        guard process.terminationStatus == 0 else { return nil }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let lines = output.split(separator: "\n").map(String.init)
        guard let root = lines.first, !root.isEmpty else { return nil }
        let branch = lines.count > 1 && lines[1] != "HEAD" ? lines[1] : nil
        return GitInfo(root: root, branch: branch)
    }

    private static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
