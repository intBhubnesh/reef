# VS Code Codex Watching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show Codex sessions that do not run hooks, notably VS Code's, on the island as read-only cards.

**Architecture:** A pure fold in `ReefCore` turns transcript records into a session; a polling watcher in `ReefApp` feeds it to the existing `SessionStore` with a new `ingress` marker. No new reducer events and no approval path.

**Tech Stack:** Swift 5 mode, SwiftPM, Foundation `JSONSerialization`, `FileHandle` offset reads, `Timer` polling.

**Spec:** `docs/superpowers/specs/2026-10-31-reef-stage3-vscode-codex.md`

## Global Constraints

- Transcripts live at `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<id>.jsonl`; the first line is `session_meta`, later lines are typed records.
- A transcript is surfaced only when `session_meta.payload.thread_source == "user"` and `parent_thread_id` is absent.
- A session id already known from hooks is never shown twice; hooks win because they carry approvals.
- Watched sessions never create a `PendingRequest`, so no approval control can appear for them.
- Reef reads metadata, turn boundaries and the agent's last message only; nothing leaves the machine.
- Reads are incremental from a stored byte offset; whole files are never re-read.
- All existing tests stay green.

## Review Focus

1. A transcript whose first line is truncated mid-write (Codex is appending as Reef reads) must yield no session and must not poison the file's offset (Task 1, Task 3).
2. A record type Reef has never seen, or a `thread_settings_applied` with no model, must be ignored rather than abort the fold (Task 1).
3. A session that ends while Reef is not running, then is read at startup, must appear as done rather than stuck working (Task 1).
4. The same session id arriving from both hooks and a transcript must leave exactly one card, with its approval buttons intact (Task 2).
5. Turning the setting off must remove watched cards immediately and leave hook sessions untouched (Task 3).

---

### Task 1: Transcript fold

**Files:**
- Create: `Sources/ReefCore/Codex/CodexTranscript.swift`
- Test: `Tests/ReefCoreTests/CodexTranscriptTests.swift`

**Interfaces:**
- Produces: `public struct TranscriptSession: Equatable { public let id: String; public let cwd: String?; public let originator: String?; public var model: String?; public var isWorking: Bool; public var lastAssistantMessage: String?; public let startedAt: Date; public var lastActivityAt: Date; public var turnCount: Int }`
- Produces: `public enum CodexTranscript { public static func begin(metaLine: Data) -> TranscriptSession?; public static func fold(_ session: inout TranscriptSession, line: Data) }`
- `begin` returns nil unless the line parses, `type == "session_meta"`, `payload.thread_source == "user"`, `payload.parent_thread_id` is absent, and `payload.id` is present. `startedAt` and `lastActivityAt` come from the record's ISO `timestamp`, falling back to now.
- `fold` updates: `task_started` → `isWorking = true`, `turnCount += 1`; `task_complete` → `isWorking = false`; `thread_settings_applied` → `model` when `thread_settings.model` is present; a `response_item` message with `role == "assistant"` → `lastAssistantMessage` from the joined `content[].text`. Every record advances `lastActivityAt` when it carries a timestamp. Unparseable or unknown lines are ignored.

- [ ] **Step 1: Write the failing tests** in `CodexTranscriptTests.swift`:

```swift
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
}
func testTurnsDriveWorkingState() {
    var s = CodexTranscript.begin(metaLine: line(meta))!
    CodexTranscript.fold(&s, line(#"{"type":"event_msg","payload":{"type":"task_started"}}"#))
    XCTAssertTrue(s.isWorking); XCTAssertEqual(s.turnCount, 1)
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
    CodexTranscript.fold(&s, line(#"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md"}]}}"#))
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
```
- [ ] **Step 2: Run `swift test --filter CodexTranscriptTests`** — expected: build failure, `CodexTranscript` undefined.
- [ ] **Step 3: Implement `TranscriptSession` and `CodexTranscript`.**
- [ ] **Step 4: Run `swift test --filter CodexTranscriptTests`** — expected: PASS.
- [ ] **Step 5: Verify against the real transcripts.** Add `testFoldsARealTranscriptWhenPresent` that skips when `~/.codex/sessions` is absent; otherwise it folds every `rollout-*.jsonl` modified today and asserts that only `thread_source: user` files yield a session and that none throws.
- [ ] **Step 6: Commit** `feat(core): fold Codex transcripts into sessions`.

---

### Task 2: Session ingress and dedupe

**Files:**
- Modify: `Sources/ReefCore/Sessions/Session.swift`, `Sources/ReefCore/Sessions/SessionReducer.swift`
- Test: `Tests/ReefCoreTests/SessionReducerTests.swift` (add)

**Interfaces:**
- Produces: `public enum SessionIngress: String, Equatable { case hook, transcript }` and `Session.ingress: SessionIngress` (default `.hook`).
- Produces: `SessionReducer.upsertWatched(_ state: inout SessionState, _ transcript: TranscriptSession, key: SessionKey, now: Date) -> [SessionEffect]` — creates or updates a `.transcript` session; returns `[]` and changes nothing when an existing session for that key has `ingress == .hook`; emits `revealCompletion` plus `sound(.done)` the first time a watched session turns from working to done.
- Produces: `SessionReducer.removeWatched(_ state: inout SessionState) -> [SessionEffect]` — drops every `.transcript` session, for the settings toggle.

- [ ] **Step 1: Write the failing tests**:

```swift
func testWatchedSessionAppearsAndTracksTurns() {
    var s = SessionState()
    var t = TranscriptSession(id: "w1", cwd: "/tmp/proj", originator: "codex_vscode", model: "gpt-5.6-sol",
                              isWorking: true, lastAssistantMessage: nil, startedAt: t0, lastActivityAt: t0, turnCount: 1)
    let key = SessionKey(source: .codex, sessionID: "w1")
    _ = SessionReducer.upsertWatched(&s, t, key: key, now: t0)
    XCTAssertEqual(s.sessions[key]?.status, .working)
    XCTAssertEqual(s.sessions[key]?.ingress, .transcript)
    XCTAssertEqual(s.sessions[key]?.project, "proj")
    XCTAssertEqual(s.sessions[key]?.model, "gpt-5.6-sol")
    t.isWorking = false; t.lastAssistantMessage = "Done."
    let effects = SessionReducer.upsertWatched(&s, t, key: key, now: t0.addingTimeInterval(5))
    XCTAssertEqual(s.sessions[key]?.status, .done)
    XCTAssertEqual(s.sessions[key]?.lastAssistantMessage, "Done.")
    XCTAssertTrue(effects.contains(.revealCompletion(key)))
}
func testHookSessionIsNeverOverwrittenByATranscript() {
    var s = SessionState()
    let key = SessionKey(source: .codex, sessionID: "dup")
    _ = SessionReducer.reduce(&s, event: codexEvent("UserPromptSubmit", session: "dup"), requestID: nil, now: t0)
    let before = s.sessions[key]
    let t = TranscriptSession(id: "dup", cwd: "/tmp/other", originator: "codex_vscode", model: nil,
                              isWorking: false, lastAssistantMessage: "x", startedAt: t0, lastActivityAt: t0, turnCount: 9)
    XCTAssertEqual(SessionReducer.upsertWatched(&s, t, key: key, now: t0), [])
    XCTAssertEqual(s.sessions[key], before, "hooks win; they carry approvals")
    XCTAssertEqual(s.sessions.count, 1)
}
func testRemoveWatchedLeavesHookSessions() {
    var s = SessionState()
    _ = SessionReducer.reduce(&s, event: codexEvent("SessionStart", session: "hooked"), requestID: nil, now: t0)
    let watched = TranscriptSession(id: "w", cwd: "/tmp/p", originator: "codex_vscode", model: nil,
                                    isWorking: true, lastAssistantMessage: nil, startedAt: t0, lastActivityAt: t0, turnCount: 1)
    _ = SessionReducer.upsertWatched(&s, watched, key: SessionKey(source: .codex, sessionID: "w"), now: t0)
    XCTAssertEqual(s.sessions.count, 2)
    let effects = SessionReducer.removeWatched(&s)
    XCTAssertEqual(s.sessions.count, 1)
    XCTAssertEqual(effects.count, 1)
}
```

  Add a `codexEvent(_:session:)` helper beside the existing `event(_:source:session:extra:)`.
- [ ] **Step 2: Run `swift test --filter SessionReducerTests`** — expected: compile failure on `ingress`.
- [ ] **Step 3: Implement** the ingress field, `upsertWatched` and `removeWatched`. A watched session's `terminal` is a `TerminalIdentity` with `bundleID = JumpPlanner.vscodeBundle`, so the existing jump engine opens VS Code at the cwd.
- [ ] **Step 4: Run `swift test --filter SessionReducerTests`** — expected: PASS.
- [ ] **Step 5: Commit** `feat(core): watched-session ingress and dedupe`.

---

### Task 3: The watcher, settings and presentation

**Files:**
- Create: `Sources/ReefApp/Codex/CodexTranscriptWatcher.swift`
- Modify: `Sources/ReefApp/App/AppState.swift`, `Sources/ReefApp/App/ReefApp.swift`, `Sources/ReefCore/Settings/ReefSettings.swift`, `Sources/ReefApp/Settings/IntegrationsTab.swift`, `Sources/ReefApp/Panel/SessionCardView.swift`
- Test: `Tests/ReefCoreTests/ReefSettingsTests.swift` (add one)

**Interfaces:**
- Consumes: `CodexTranscript` (Task 1), `SessionReducer.upsertWatched` / `removeWatched` (Task 2).
- Produces: `ReefSettings.watchCodexTranscripts: Bool = true`.
- Produces: `@MainActor final class CodexTranscriptWatcher { init(root: URL, onSession: @escaping (TranscriptSession) -> Void); func start(); func stop(); func scanOnce() }` — every 2 s lists `rollout-*.jsonl` under `root` modified within 30 minutes; per file keeps `(offset, session?)`; reads only the tail past `offset`; a file whose first line fails `begin` is recorded as ignored and skipped from then on; a partial trailing line (no newline) is left unconsumed so the offset stops at the last complete line.
- Produces: `AppState.watchedSessionsEnabled` wiring: starting and stopping the watcher when the setting changes, and calling `removeWatched` when it is turned off.
- `SessionCardView` shows a "watched" chip for `.transcript` sessions, with help text explaining approvals happen in the editor.

- [ ] **Step 1: Write the failing settings test** in `ReefSettingsTests.swift`:

```swift
func testWatchCodexTranscriptsDefaultsOnAndRoundTrips() throws {
    XCTAssertTrue(ReefSettings().watchCodexTranscripts)
    var s = ReefSettings(); s.watchCodexTranscripts = false
    let url = tempURL(); try s.save(to: url)
    XCTAssertFalse(ReefSettings.load(from: url).watchCodexTranscripts)
}
```
- [ ] **Step 2: Run `swift test --filter ReefSettingsTests`** — expected: compile failure.
- [ ] **Step 3: Implement** the setting, the watcher, the AppState wiring, the Settings row and the card marker.
- [ ] **Step 4: Run `swift test`** — expected: all green.
- [ ] **Step 5: Manual verification.** With Reef running and a Codex session open in VS Code: the session appears within 5 s with the right project and a Codex chip; it reads working during a turn and done after, with the closing message; no `guardian_review` subagent appears; a terminal Codex session appears exactly once and keeps its Allow and Deny buttons; clicking a watched card focuses VS Code; turning the setting off removes the watched cards and leaves the hook ones.
- [ ] **Step 6: Commit** `feat(app): watch Codex transcripts from other editors`.

---

### Task 4: Acceptance and documentation

**Files:**
- Create: `docs/acceptance-vscode-codex.md`
- Modify: `docs/protocol.md` (a section on the transcript ingress), `README.md` (one line)

- [ ] **Step 1: Run the spec's eight acceptance criteria**, recording PASS/PARTIAL/FAIL with evidence.
- [ ] **Step 2: Document the second ingress** in `docs/protocol.md`: where transcripts live, the subagent filter, the dedupe rule, and that watched sessions are read-only.
- [ ] **Step 3: Commit** `docs: VS Code Codex acceptance` and tag `v0.3.0`.

---

## Self-review notes

- Spec coverage: goals 1–3 → Tasks 1 and 3; goal 4 → Task 2; goal 5 → Task 1's filter; goal 6 → Task 3. Non-goal "approvals" is enforced structurally, since no task creates a `PendingRequest` for a watched session.
- Review Focus coverage: (1) `testBeginRejectsReviewSubagentsAndJunk` plus the watcher's partial-line rule in Task 3; (2) `testUnknownAndBrokenRecordsAreIgnored`; (3) `testEndedSessionReadAtStartupIsDoneNotWorking`; (4) `testHookSessionIsNeverOverwrittenByATranscript`; (5) `testRemoveWatchedLeavesHookSessions` plus the Task 3 manual check.
- Type consistency: `TranscriptSession`, `CodexTranscript.begin/fold`, `SessionIngress`, `upsertWatched`, `removeWatched`, `watchCodexTranscripts` are used under the same names throughout.
