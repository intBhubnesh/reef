import XCTest
@testable import ReefCore

final class CodexTranscriptTests: XCTestCase {
    private func line(_ s: String) -> Data { s.data(using: .utf8)! }
    private let meta = #"{"timestamp":"2026-10-31T17:27:19.792Z","type":"session_meta","payload":{"id":"abc","cwd":"/Users/x/proj","originator":"codex_vscode","thread_source":"user"}}"#

    func testBeginAcceptsAUserConversation() {
        let s = CodexTranscript.begin(metaLine: line(meta))
        XCTAssertEqual(s?.id, "abc")
        XCTAssertEqual(s?.cwd, "/Users/x/proj")
        XCTAssertEqual(s?.originator, "codex_vscode")
        XCTAssertFalse(s?.isWorking ?? true)
        XCTAssertEqual(s?.turnCount, 0)
    }

    func testBeginRejectsReviewSubagentsAndJunk() {
        let sub = #"{"type":"session_meta","payload":{"id":"s","thread_source":"guardian_review","parent_thread_id":"p"}}"#
        XCTAssertNil(CodexTranscript.begin(metaLine: line(sub)))
        let parented = #"{"type":"session_meta","payload":{"id":"s","thread_source":"user","parent_thread_id":"p"}}"#
        XCTAssertNil(CodexTranscript.begin(metaLine: line(parented)))
        XCTAssertNil(CodexTranscript.begin(metaLine: line(#"{"type":"session_meta","payload":{"id":"s","thread_sou"#)))
        XCTAssertNil(CodexTranscript.begin(metaLine: line("not json")))
        XCTAssertNil(CodexTranscript.begin(metaLine: Data()))
        XCTAssertNil(CodexTranscript.begin(metaLine: line(#"{"type":"event_msg","payload":{"type":"task_started"}}"#)))
        XCTAssertNil(CodexTranscript.begin(metaLine: line(#"{"type":"session_meta","payload":{"thread_source":"user"}}"#)),
                     "no id is not a session")
    }

    func testTurnsDriveWorkingState() {
        var s = CodexTranscript.begin(metaLine: line(meta))!
        CodexTranscript.fold(&s, line(#"{"type":"event_msg","payload":{"type":"task_started"}}"#))
        XCTAssertTrue(s.isWorking)
        XCTAssertEqual(s.turnCount, 1)
        CodexTranscript.fold(&s, line(#"{"type":"event_msg","payload":{"type":"task_complete"}}"#))
        XCTAssertFalse(s.isWorking)
        CodexTranscript.fold(&s, line(#"{"type":"event_msg","payload":{"type":"task_started"}}"#))
        XCTAssertEqual(s.turnCount, 2)
    }

    func testEndedSessionReadAtStartupIsDoneNotWorking() {
        var s = CodexTranscript.begin(metaLine: line(meta))!
        for _ in 0..<3 {
            CodexTranscript.fold(&s, line(#"{"type":"event_msg","payload":{"type":"task_started"}}"#))
            CodexTranscript.fold(&s, line(#"{"type":"event_msg","payload":{"type":"task_complete"}}"#))
        }
        XCTAssertFalse(s.isWorking)
        XCTAssertEqual(s.turnCount, 3)
    }

    func testModelAndAssistantMessage() {
        var s = CodexTranscript.begin(metaLine: line(meta))!
        CodexTranscript.fold(&s, line(#"{"type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"model":"gpt-5.6-sol"}}}"#))
        XCTAssertEqual(s.model, "gpt-5.6-sol")
        CodexTranscript.fold(&s, line(#"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Fixed it."}]}}"#))
        XCTAssertEqual(s.lastAssistantMessage, "Fixed it.")
        CodexTranscript.fold(&s, line(##"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md"}]}}"##))
        XCTAssertEqual(s.lastAssistantMessage, "Fixed it.", "user messages are injected context, not shown")
    }

    func testUnknownAndBrokenRecordsAreIgnored() {
        var s = CodexTranscript.begin(metaLine: line(meta))!
        let before = s
        CodexTranscript.fold(&s, line(#"{"type":"future_record","payload":{"whatever":1}}"#))
        CodexTranscript.fold(&s, line(#"{"type":"event_msg","payload":{"type":"thread_settings_applied"}}"#))
        CodexTranscript.fold(&s, line("{\"type\":\"event_msg\",\"payl"))
        CodexTranscript.fold(&s, Data())
        XCTAssertEqual(s.isWorking, before.isWorking)
        XCTAssertEqual(s.turnCount, before.turnCount)
        XCTAssertNil(s.model)
    }

    func testTimestampsAdvanceActivity() {
        var s = CodexTranscript.begin(metaLine: line(meta))!
        let started = s.lastActivityAt
        CodexTranscript.fold(&s, line(#"{"timestamp":"2026-10-31T17:40:00.000Z","type":"event_msg","payload":{"type":"task_started"}}"#))
        XCTAssertGreaterThan(s.lastActivityAt, started)
    }

    func testBeginRejectsFrontEndsThatRunHooks() {
        // codex-tui and codex exec deliver their own events, so reading their transcripts too
        // would show the session twice, or resurrect it after its hooks said it ended.
        func metaLine(originator: String) -> Data {
            line(##"{"type":"session_meta","payload":{"id":"abc","thread_source":"user","originator":"\##(originator)"}}"##)
        }
        for originator in ["codex-tui", "codex_exec"] {
            XCTAssertNil(CodexTranscript.begin(metaLine: metaLine(originator: originator)), "\(originator) runs hooks")
        }
        XCTAssertNotNil(CodexTranscript.begin(metaLine: metaLine(originator: "codex_vscode")))
        XCTAssertNotNil(CodexTranscript.begin(metaLine: metaLine(originator: "something_new")),
                        "an unknown front end is assumed hookless, which is the case worth showing")
    }

    func testCompleteLinesLeavesAPartialRecordForTheNextPass() {
        // A transcript is read while Codex is appending to it, so the last line is often half
        // written. Consuming it would feed JSON fragments to the parser.
        let data = Data("{\"a\":1}\n{\"b\":2}\n{\"c\":".utf8)
        let (lines, consumed) = CodexTranscript.completeLines(in: data)
        XCTAssertEqual(lines.map { String(decoding: $0, as: UTF8.self) }, ["{\"a\":1}", "{\"b\":2}"])
        XCTAssertEqual(consumed, 16, "the half-written record stays unread")
    }

    func testCompleteLinesConsumesNothingWithoutANewline() {
        let (lines, consumed) = CodexTranscript.completeLines(in: Data("{\"half\":".utf8))
        XCTAssertTrue(lines.isEmpty)
        XCTAssertEqual(consumed, 0)
    }

    func testCompleteLinesSkipsBlankLines() {
        let (lines, consumed) = CodexTranscript.completeLines(in: Data("a\n\n\nb\n".utf8))
        XCTAssertEqual(lines.map { String(decoding: $0, as: UTF8.self) }, ["a", "b"])
        XCTAssertEqual(consumed, 6)
    }

    func testAnAbortedTurnIsNotStillWorking() {
        // Pressing Stop in the editor writes turn_aborted and never a task_complete.
        var session = CodexTranscript.begin(metaLine: line(meta))!
        CodexTranscript.fold(&session, line(#"{"type":"event_msg","payload":{"type":"task_started"}}"#))
        XCTAssertTrue(session.isWorking)
        CodexTranscript.fold(&session, line(#"{"type":"event_msg","payload":{"type":"turn_aborted"}}"#))
        XCTAssertFalse(session.isWorking)
    }

    /// Folds this machine's real transcripts when they exist, which is the only way to know the
    /// parser matches what Codex actually writes. Skips cleanly on a machine without them.
    func testFoldsARealTranscriptWhenPresent() throws {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw XCTSkip("no Codex transcripts on this machine")
        }
        var files: [URL] = []
        if let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for case let url as URL in walker where url.lastPathComponent.hasPrefix("rollout-") {
                files.append(url)
            }
        }
        guard !files.isEmpty else { throw XCTSkip("no rollout files") }
        var accepted = 0, rejected = 0
        // Real transcripts reach hundreds of megabytes; reading the large ones would cost more
        // than the rest of the suite and prove nothing extra about the record shapes.
        let small = files.filter { (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 < 2 << 20 }
        for url in small.suffix(40) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map { Data($0.utf8) }
            guard !lines.isEmpty else { continue }
            guard var session = CodexTranscript.begin(metaLine: lines.removeFirst()) else { rejected += 1; continue }
            for line in lines { CodexTranscript.fold(&session, line) }
            accepted += 1
            XCTAssertFalse(session.id.isEmpty)
            XCTAssertGreaterThanOrEqual(session.turnCount, 0)
        }
        // The point of this test is that the parser still matches what Codex writes. Accepting
        // nothing is exactly the failure a renamed field would cause, so it must not pass.
        XCTAssertGreaterThan(accepted, 0, "no real transcript parsed: Codex's record shape has moved")
        if rejected == 0 { print("note: no subagent transcripts in this sample") }
    }
}
