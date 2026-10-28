import XCTest
@testable import ReefCore

final class GitInfoTests: XCTestCase {
    private func makeTempDir() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("reef-git-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func git(_ args: [String], in dir: URL) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        p.currentDirectoryURL = dir
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try! p.run(); p.waitUntilExit()
        return p.terminationStatus
    }

    func testGitInfoLookupInTempRepo() {
        let dir = makeTempDir()
        git(["init", "-q", "-b", "trunk"], in: dir)
        git(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init"], in: dir)
        let sub = dir.appendingPathComponent("sub")
        try! FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let info = GitInfo.lookup(cwd: sub.path, cacheDir: nil)
        XCTAssertEqual(URL(fileURLWithPath: info?.root ?? "/none").standardizedFileURL.resolvingSymlinksInPath().path,
                       dir.standardizedFileURL.resolvingSymlinksInPath().path)
        XCTAssertEqual(info?.branch, "trunk")
    }

    func testGitInfoNilOutsideRepo() {
        let dir = makeTempDir()
        XCTAssertNil(GitInfo.lookup(cwd: dir.path, cacheDir: nil))
    }

    func testGitInfoUsesCache() {
        let dir = makeTempDir()
        git(["init", "-q", "-b", "main"], in: dir)
        git(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init"], in: dir)
        let cache = makeTempDir()
        XCTAssertEqual(GitInfo.lookup(cwd: dir.path, cacheDir: cache)?.branch, "main")
        git(["checkout", "-q", "-b", "other"], in: dir)
        XCTAssertEqual(GitInfo.lookup(cwd: dir.path, cacheDir: cache)?.branch, "main", "cached for 60 s")
        XCTAssertEqual(GitInfo.lookup(cwd: dir.path, cacheDir: nil)?.branch, "other")
    }
}
