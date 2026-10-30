import XCTest
@testable import ReefCore

/// Regression tests for the final-review findings.
final class ReviewFixTests: XCTestCase {
    private func tempFile(_ contents: String?) -> String {
        let path = NSTemporaryDirectory() + "reef-hooks-\(UUID().uuidString).json"
        if let contents { FileManager.default.createFile(atPath: path, contents: contents.data(using: .utf8)) }
        return path
    }

    // #2 unparseable settings must never be overwritten
    func testTransformLeavesUnparseableFileUntouched() {
        let path = tempFile("{ this is not json")
        let ok = HookFiles.transform(file: path) { HookConfig.install(into: $0, source: .claude) }
        XCTAssertFalse(ok)
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "{ this is not json")
    }

    func testTransformCreatesMissingFileAndPreservesMode() throws {
        let path = tempFile(nil)
        XCTAssertTrue(HookFiles.transform(file: path) { HookConfig.install(into: $0, source: .codex) })
        XCTAssertNotNil(HookFiles.read(file: path)?["hooks"])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        XCTAssertTrue(HookFiles.transform(file: path) { HookConfig.uninstall(from: $0, source: .codex) })
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }

    // #4 huge files must not be diffed in full
    func testPresentationFallsBackToSummaryForHugeFiles() {
        let huge = (1...3000).map { "line \($0)" }.joined(separator: "\n")
        let p = ApprovalPresentation.make(toolName: "Write", toolInput: ["file_path": "/p/big.txt", "content": huge], source: .claude) { _ in huge + "\nx" }
        guard case let .summary(title, detail) = p else { return XCTFail("expected summary, got \(p)") }
        XCTAssertEqual(title, "Write")
        XCTAssertTrue(detail.contains("/p/big.txt"))
        XCTAssertTrue(detail.contains("3001"), "mentions the size so the user knows why there is no diff")
    }

    func testEditOnHugeFileDiffsOnlyTheChange() {
        let huge = (1...3000).map { "line \($0)" }.joined(separator: "\n")
        let p = ApprovalPresentation.make(toolName: "Edit", toolInput: ["file_path": "/p/big.txt", "old_string": "line 1500", "new_string": "LINE"], source: .claude) { _ in huge }
        guard case let .diff(_, lines) = p else { return XCTFail("expected diff") }
        XCTAssertLessThan(lines.count, 20)
        XCTAssertEqual(lines.filter { $0.kind == .removed }.map(\.text), ["line 1500"])
    }

    // #6 a question card with no parseable questions must not be submittable
    func testEmptyQuestionsCannotSubmit() {
        XCTAssertFalse(QuestionSelection(questions: []).canSubmit)
    }

    // #7 focus release must match the kitty window, not only the app
    func testFocusMatchRequiresKittyWindowWhenKnown() {
        let t = TerminalIdentity(tty: "/dev/ttys1", bundleID: "net.kovidgoyal.kitty", termProgram: "kitty", kittyWindowID: 7)
        XCTAssertTrue(FocusMatch.isFocused(t, frontmostBundleID: "net.kovidgoyal.kitty", focusedKittyWindows: [7]))
        XCTAssertFalse(FocusMatch.isFocused(t, frontmostBundleID: "net.kovidgoyal.kitty", focusedKittyWindows: [2]))
        XCTAssertTrue(FocusMatch.isFocused(t, frontmostBundleID: "net.kovidgoyal.kitty", focusedKittyWindows: nil), "unknown focus falls back to the app match")
        XCTAssertFalse(FocusMatch.isFocused(t, frontmostBundleID: "com.apple.finder", focusedKittyWindows: [7]))
        let other = TerminalIdentity(tty: "/dev/ttys2", bundleID: "com.mitchellh.ghostty")
        XCTAssertTrue(FocusMatch.isFocused(other, frontmostBundleID: "com.mitchellh.ghostty", focusedKittyWindows: nil))
    }

    // #8 deletes must be labelled, never shown as "No changes"
    func testApplyPatchDeleteIsLabelled() {
        let files = ApplyPatch.files(from: "*** Begin Patch\n*** Delete File: old.txt\n*** Update File: a.txt\n@@\n-x\n+y\n*** End Patch")
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].kind, .delete)
        XCTAssertEqual(files[0].path, "old.txt")
        XCTAssertEqual(files[1].kind, .update)
        XCTAssertEqual(ApplyPatch.files(from: "*** Begin Patch\n*** Add File: n.txt\n+hi\n*** End Patch").first?.kind, .add)
    }
}
