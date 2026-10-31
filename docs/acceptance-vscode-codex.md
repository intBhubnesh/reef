# Reef VS Code Codex acceptance — 2026-10-31

Run on a 14-inch MacBook Pro (macOS 26, Apple Silicon) with Codex 0.166.0 and `dist/Reef.app` built by `scripts/bundle.sh` (universal, ad hoc signed). Spec: `docs/superpowers/specs/2026-10-31-reef-stage3-vscode-codex.md`. Suite: **171 tests, 0 failures**.

Runtime evidence is Reef's own log (`~/Library/Logs/Reef/reef.log`), which records every watched session as it is first seen, every hook event received, and every completion sound. Lifecycle criteria were driven by appending real-shaped records to a transcript file while Reef ran, because the VS Code extension cannot be driven from a script. The record shapes themselves were validated against this machine's 1316 real October transcripts in `CodexTranscriptTests.testFoldsARealTranscriptWhenPresent`.

## Criteria

| # | Criterion | Result | Evidence |
|---|---|---|---|
| 1 | A Codex session in VS Code appears within 5 s with the right project | PASS | A `codex_vscode` transcript written at 17:54:54 was on the island at 17:54:58, **4 s**, logged as `watched session id=acc-vscode-2 project=reef`. Poll interval is 2 s. |
| 2 | Working while the turn runs; done with the closing message when it ends | PASS | After `task_started` the session showed working, and `task_complete` produced the `sound done` effect at 17:55:06, 4 s after the record was appended. The closing message itself is asserted by `testWatchedSessionAppearsAndTracksTurns` (`lastAssistantMessage == "Done."`); the log does not carry card text. |
| 3 | `guardian_review` subagents never appear | PASS | A subagent meta record written alongside the real one produced no session. On this machine 1255 of 1316 October transcripts are `guardian_review` or `subagent` runs and none has ever been logged as watched. `testBeginRejectsReviewSubagentsAndJunk`. |
| 4 | A terminal Codex session appears exactly once, through hooks, approvals intact | PASS, after a fix | First run **failed**: `codex exec` arrived through hooks (`SessionStart`, `UserPromptSubmit`, `Stop`, `SessionEnd`), and 13 s later the watcher resurrected the same id as a watched session, because `SessionEnd` had removed the hook session that the dedupe check looks for. Fixed by rejecting the originators that run hooks (`codex-tui`, `codex_cli`, `codex_exec`). Re-run: four hook events for session `01a1931b`, no watched duplicate. |
| 5 | Clicking a watched session focuses VS Code | PASS, not clicked | A watched session carries `TerminalIdentity(bundleID: JumpPlanner.vscodeBundle)` and the card's button stays enabled, so `JumpPlanner.plan` emits `.vscodeOpen` with the cwd. Verified as a code path and by the pre-flight check in the ledger, not by a click on screen. |
| 6 | Turning the setting off removes watched sessions and stops polling | PASS | Launched with `watchCodexTranscripts: false`: **0** codex lines in the log, no `watching transcripts`, 2 log lines total. The removal half is `testRemoveWatchedLeavesHookSessions`, which also proves hook sessions survive. |
| 7 | A truncated, malformed or unknown transcript neither crashes the watcher nor makes a session | PASS | A file containing `{not json` plus a line with no terminating newline produced no session, and the watcher kept reading other files in the same pass. `testUnknownAndBrokenRecordsAreIgnored`, plus the partial-line rule in `CodexTranscriptWatcher.readNewLines`. |
| 8 | `swift test` green, Stage 1 and 2 acceptance still hold | PASS | 171 tests, 0 failures. The only change to the hook path is one line in `SessionReducer.reduce` setting `ingress = .hook`, which no Stage 1 or 2 behaviour reads. |

## Two defects the runtime pass caught

Both were invisible to the unit tests and only appeared with the app running:

- **A session flashed done the moment it started.** The first record of a transcript is `session_meta`, with no turn yet, and `isWorking == false` was read as finished. A brand-new VS Code session therefore announced a completion before its first turn. Now a transcript with no turn and no assistant message shows idle (`testASessionWithNoTurnsYetIsIdleNotDone`).
- **The panel opened on launch for sessions that had already ended.** Every finished session inside the 30-minute lookback was a first sighting in the done state, so each one revealed the panel and played a sound. A completion is now announced only when it happens while Reef is watching (`testAFinishedSessionSeenForTheFirstTimeIsSilent`).

## Limits

- The VS Code extension was never driven end to end by this pass. Record shapes come from real transcripts, but the extension's own timing with Reef running has not been observed.
- Offsets are in memory. A relaunch re-folds every transcript inside the lookback, which is how criteria 1 and 6 were measured, and is why the silent-first-sighting rule matters.
- A terminal Codex session whose hooks are not installed or not trusted stays invisible: its originator is on the rejected list. Settings → Integrations reports both states.
- Approvals in watched sessions happen in the editor. Speaking the app-server protocol is a separate stage.
