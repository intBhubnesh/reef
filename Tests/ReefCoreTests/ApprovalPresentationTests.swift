import XCTest
@testable import ReefCore

final class ApprovalPresentationTests: XCTestCase {
    func testLineDiffAddRemove() {
        let lines = LineDiff.compute(old: "a\nb\nc", new: "a\nx\nc")
        XCTAssertEqual(lines.map(\.kind), [.context, .removed, .added, .context])
        XCTAssertEqual(lines.map(\.text), ["a", "b", "x", "c"])
        XCTAssertEqual(lines.map(\.oldNumber), [1, 2, nil, 3])
        XCTAssertEqual(lines.map(\.newNumber), [1, nil, 2, 3])
    }

    func testLineDiffCollapsesContext() {
        let base = (1...20).map { "line \($0)" }
        var changed = base; changed[10] = "CHANGED"
        let lines = LineDiff.compute(old: base.joined(separator: "\n"), new: changed.joined(separator: "\n"))
        XCTAssertLessThanOrEqual(lines.count, 8)
        XCTAssertEqual(lines.filter { $0.kind == .removed }.map(\.text), ["line 11"])
        XCTAssertEqual(lines.filter { $0.kind == .added }.map(\.text), ["CHANGED"])
        XCTAssertEqual(lines.first?.text, "line 8")
    }

    func testLineDiffIdenticalIsEmpty() {
        XCTAssertEqual(LineDiff.compute(old: "same\nsame", new: "same\nsame"), [])
    }

    func testApplyPatchParsesUpdateAndAdd() {
        let patch = """
        *** Begin Patch
        *** Update File: src/a.swift
        @@ func x()
         let a = 1
        -let b = 2
        +let b = 3
         return a + b
        *** Add File: src/new.txt
        +hello
        +world
        *** End Patch
        """
        let files = ApplyPatch.files(from: patch)
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].path, "src/a.swift")
        XCTAssertEqual(files[0].lines.map(\.kind), [.context, .removed, .added, .context])
        XCTAssertEqual(files[0].lines[1].text, "let b = 2")
        XCTAssertEqual(files[1].path, "src/new.txt")
        XCTAssertEqual(files[1].lines.map(\.kind), [.added, .added])
    }

    func testEditPresentationUsesFileContext() {
        let input: [String: Any] = ["file_path": "/p/f.txt", "old_string": "OLD", "new_string": "NEW"]
        let p = ApprovalPresentation.make(toolName: "Edit", toolInput: input, source: .claude) { _ in "l1\nOLD\nl3" }
        guard case let .diff(path, lines) = p else { return XCTFail("expected diff, got \(p)") }
        XCTAssertEqual(path, "/p/f.txt")
        XCTAssertEqual(lines.map(\.text), ["l1", "OLD", "NEW", "l3"])
        XCTAssertEqual(lines.map(\.kind), [.context, .removed, .added, .context])
    }

    func testEditPresentationFallsBackWithoutFile() {
        let input: [String: Any] = ["file_path": "/p/f.txt", "old_string": "OLD", "new_string": "NEW"]
        let p = ApprovalPresentation.make(toolName: "Edit", toolInput: input, source: .claude) { _ in nil }
        guard case let .diff(_, lines) = p else { return XCTFail("expected diff") }
        XCTAssertEqual(lines.map(\.kind), [.removed, .added])
    }

    func testWritePresentationNewFile() {
        let p = ApprovalPresentation.make(toolName: "Write", toolInput: ["file_path": "/p/n.txt", "content": "a\nb"], source: .claude) { _ in nil }
        guard case let .diff(_, lines) = p else { return XCTFail("expected diff") }
        XCTAssertEqual(lines.map(\.kind), [.added, .added])
    }

    func testBashPresentation() {
        let p = ApprovalPresentation.make(toolName: "Bash", toolInput: ["command": "rm -rf build", "description": "Clean"], source: .claude) { _ in nil }
        XCTAssertEqual(p, .bash(command: "rm -rf build", description: "Clean"))
        let codex = ApprovalPresentation.make(toolName: "shell", toolInput: ["command": ["ls", "-la"]], source: .codex) { _ in nil }
        XCTAssertEqual(codex, .bash(command: "ls -la", description: nil))
    }

    func testApplyPatchPresentation() {
        let patch = "*** Begin Patch\n*** Add File: x.txt\n+hi\n*** End Patch"
        let p = ApprovalPresentation.make(toolName: "apply_patch", toolInput: ["patch": patch], source: .codex) { _ in nil }
        guard case let .multiDiff(files) = p else { return XCTFail("expected multiDiff") }
        XCTAssertEqual(files.map(\.path), ["x.txt"])
    }

    func testSummaryTools() {
        XCTAssertEqual(ApprovalPresentation.make(toolName: "Read", toolInput: ["file_path": "/a/b.txt"], source: .claude) { _ in nil },
                       .summary(title: "Read", detail: "/a/b.txt"))
        XCTAssertEqual(ApprovalPresentation.make(toolName: "WebFetch", toolInput: ["url": "https://x.y", "prompt": "p"], source: .claude) { _ in nil },
                       .summary(title: "WebFetch", detail: "https://x.y"))
    }

    func testUnknownToolIsPrettyJSON() {
        let p = ApprovalPresentation.make(toolName: "mcp__foo__bar", toolInput: ["z": 1, "a": "x"], source: .claude) { _ in nil }
        guard case let .json(tool, pretty) = p else { return XCTFail("expected json") }
        XCTAssertEqual(tool, "mcp__foo__bar")
        XCTAssertTrue(pretty.contains("\"a\" : \"x\""))
        XCTAssertLessThan(pretty.range(of: "\"a\"")!.lowerBound, pretty.range(of: "\"z\"")!.lowerBound)
    }
}
