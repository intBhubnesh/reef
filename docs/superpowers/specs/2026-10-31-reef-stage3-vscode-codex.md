# Reef — watching Codex sessions that do not run hooks

Date: 2026-10-31. Status: draft for approval. Follows Stage 2 (`v0.2.0`).

## Intent

Codex in VS Code is invisible to Reef. The user hit this today: real work running in their editor never appears on the island, which makes the island look broken rather than idle.

The cause is structural, not configuration. The VS Code extension ships its own Codex binary and runs it in app-server mode, which does not execute `~/.codex/hooks.json`. Measured on this machine: session `01a19300` (originator `codex_vscode`) produced zero Reef log entries, while `01a192fb` (originator `codex-tui`) produced eleven.

Every Codex session, whichever front end, writes a transcript to `~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<id>.jsonl`. This stage reads those transcripts so hook-less sessions appear on the island.

## Goals

1. A Codex session running in VS Code appears on the island within a few seconds of starting, with its project, status, elapsed time and a Codex chip.
2. Its status tracks the real turn: working while a turn runs, done when it ends, with the agent's closing message on the completion card.
3. Clicking it focuses VS Code on that project.
4. Sessions that already arrive through hooks are never shown twice.
5. Codex's internal review subagents never appear as sessions.
6. The user can turn the whole thing off in Settings.

## Non-goals

- **Approvals.** A transcript is a record, not a control channel. These sessions are read-only on the island: no Allow, Deny or answer. Approving from the notch would need to speak the app-server protocol, which is its own stage.
- Reading transcripts for Claude Code, which already has working hooks.
- Back-filling sessions that ended before Reef started.
- Token or cost display, although `token_count` records are present.

## Anti-goals

- **Showing noise.** Codex writes a transcript per internal subagent too. On this machine six of today's ten transcripts are `guardian_review` subagents of two real conversations. Surfacing those would make the island useless.
- **Reading the user's content further than needed.** Reef reads the session's metadata, its turn boundaries and the agent's last message. It does not index the conversation, and nothing leaves the machine.
- **Re-reading whole files.** Transcripts grow to thousands of lines; the watcher reads incrementally from a stored offset.

## What the transcript provides

The first line is `session_meta`; every later line is a typed record. Measured fields:

| Need | Source |
|---|---|
| Session id | `session_meta.payload.id`, the same value Codex sends as `session_id` in hooks, which makes dedupe exact |
| Project | `session_meta.payload.cwd` |
| Front end | `session_meta.payload.originator`: `codex_vscode`, `codex-tui` |
| Real conversation or subagent | `session_meta.payload.thread_source` is `user` for conversations and `guardian_review` for review subagents; subagents also carry `parent_thread_id` |
| Model | `event_msg.payload.thread_settings_applied.thread_settings.model` |
| Turn start / end | `event_msg.payload.type` is `task_started` / `task_complete` |
| Closing message | the last `response_item` with `payload.type == "message"` and `role == "assistant"` |

**The typed prompt is not reliably recoverable.** Every user-role message in a real conversation is injected context: the repository's AGENTS.md, the IDE's open tabs, skill definitions. The design does not show a `You:` line for watched sessions rather than show injected text as if the user typed it.

## Decided: how it works

### 1. Parsing (ReefCore, pure)

`CodexTranscript.parse(lines:now:)` folds the records into a `TranscriptSession`: `id`, `cwd`, `originator`, `model`, `status` (`.working` while a `task_started` has no matching `task_complete`, else `.done`), `lastAssistantMessage`, `startedAt`, `lastActivityAt`, `turnCount`.

It returns nil unless `thread_source == "user"` and `parent_thread_id` is absent, which is the subagent filter. Unknown record types are ignored, so a Codex update that adds records does not break it.

Parsing is incremental: the caller passes only the lines added since the last read, plus the previously folded session.

### 2. Watching (ReefApp)

`CodexTranscriptWatcher` polls `~/.codex/sessions/` every 2 s, considering only files modified in the last 30 minutes, which keeps the scan to a handful of files. For each it keeps a byte offset and reads only the new tail. A file whose first line fails the filter is remembered as ignored and never reopened.

### 3. Feeding the session store

Watched sessions enter through the same `SessionStore` as hook sessions, with `ingress: .transcript` and a `TerminalIdentity` carrying VS Code's bundle id and the cwd, so the existing jump engine focuses VS Code. `SessionReducer` gains no new event types: the watcher translates to the statuses the store already knows.

Dedupe: when a session id already exists from hooks, the watcher skips it entirely. Hooks win, because they carry approvals.

### 4. Presentation

A watched session's card shows its project, status, model and elapsed time with the Codex chip, plus a small "watched" marker explaining that approvals happen in the editor. No approval buttons can appear, because no `PendingRequest` is ever created for it.

### 5. Settings

Integrations gains "Watch Codex sessions from other editors", default on, with one line explaining that VS Code's Codex does not run hooks so Reef reads its transcripts instead, and that those sessions are read-only.

## Left to the builder

- Poll interval and lookback window, within reason.
- Where the offsets live (in memory is acceptable; sessions are re-folded on relaunch).
- The exact wording of the watched marker.

## Acceptance

1. Starting a Codex session in VS Code makes it appear on the island within 5 s with the right project.
2. While a turn runs it shows as working; when the turn ends it shows done with the agent's closing message.
3. Codex's `guardian_review` subagents never appear.
4. A Codex session in a terminal appears exactly once, through hooks, with its approval buttons intact.
5. Clicking a watched session focuses VS Code.
6. Turning the setting off removes watched sessions and stops the polling.
7. A transcript that is truncated, malformed, or in a shape Reef does not know does not crash the watcher or produce a session.
8. `swift test` stays green, and Stage 1 and 2 acceptance still hold.
