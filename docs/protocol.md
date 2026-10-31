# Reef protocol reference

Kept current with the code in `Sources/ReefCore`. Verified against Claude Code 2.1.267 and Codex 0.140.0 hook references (see the design document for the saved copies).

## 1. Hook entries Reef installs

Command (identical for both agents except the source name):

```
/bin/sh -c '[ -x "$HOME/.reef/bin/reef-bridge" ] && "$HOME/.reef/bin/reef-bridge" --source claude; exit 0'
```

| Agent | File | Events | Matcher | Timeout (s) |
|---|---|---|---|---|
| Claude Code | `~/.claude/settings.json` → `hooks` | SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest, Notification, Stop, StopFailure, SubagentStart, SubagentStop, SessionEnd, PreCompact, PostCompact | `"*"` on the four tool events, none otherwise | 3600 for PermissionRequest, 5 otherwise |
| Codex | `~/.codex/hooks.json` → `hooks` | SessionStart, SessionEnd, UserPromptSubmit, PreToolUse, PermissionRequest, PostToolUse, PreCompact, PostCompact, SubagentStart, SubagentStop, Stop, Interrupt | `startup\|resume\|clear` on SessionStart, `manual\|auto` on compaction | 3600 PermissionRequest, 1 SessionEnd/Interrupt, 5 otherwise |

Claude Code also gets `env.CLAUDE_CODE_DISABLE_TERMINAL_TITLE = "1"` so the bridge's OSC 2 title marker survives. Codex requires the user to trust the entries with `/hooks`; Reef reads `[hooks.state."<path>:<snake_event>:<entry index>:<hook index>"]` from `~/.codex/config.toml` to show the state. Entries are recognised by the `$HOME/.reef/bin/reef-bridge` substring; other apps' entries are never touched.

## 2. Bridge behaviour

- Reads stdin, parses `hook_event_name` and `session_id`; anything else → prints `{}` and exits 0.
- Adds `"source"` and a `"reef"` object: `{ "tty", "pid", "ppid", "env": {TERM_PROGRAM, TERM_SESSION_ID, ITERM_SESSION_ID, KITTY_WINDOW_ID, KITTY_PID, KITTY_LISTEN_ON, GHOSTTY_RESOURCES_DIR, TMUX, TMUX_PANE, VSCODE_PID, __CFBundleIdentifier}, "git": {"root","branch"}?, "title_marker"? }`.
- On SessionStart and UserPromptSubmit with a tty, writes `ESC ] 2 ; <project> · reef:<first 8 chars of session_id> BEL` to the tty.
- Mode: `PermissionRequest` → `wait` (reply awaited up to 3600 s); every other event → `fire` (2 s send cap).
- Any failure (no app, no socket, timeout, bad reply) → `{}`, exit 0, so the agent's own prompt stays in charge.

## 3. Socket framing

Unix domain stream socket at `~/.reef/run/reef.sock` (mode 0600). One JSON object per line, UTF-8, `\n` terminated.

```
request  {"v":1,"id":"<uuid>","mode":"fire"|"wait","event":{...enriched hook JSON...}}
response {"v":1,"id":"<same>","reply":{...}}        (wait mode only; `{}` means "no decision")
```

`fire` connections are closed by the server after parsing. `wait` connections stay open until the UI decides, the user focuses the terminal, the app quits, or the deadline passes; all of those reply `{}` except an explicit decision.

## 4. Decision JSON written to the hook's stdout

```json
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from Reef"}}}
```

- **Always allow** (Claude Code only): `allow` plus `"updatedPermissions": [<one of the request's permission_suggestions>]`, or `[{"type":"addRules","behavior":"allow","destination":"session","rules":[{"toolName":"<tool>"}]}]` when none was offered. Codex gets a plain allow.
- **AskUserQuestion**: `allow` with `updatedInput` = original `questions` plus `"answers": {"<question text>": "<label>, <label>"}`.
- **ExitPlanMode**: `allow` with `updatedInput` = `{"plan", "planFilePath"}` echoed; deny carries the user's feedback in `message`.
- Codex accepts the same `hookSpecificOutput.decision.{behavior,message}` shape and ignores `updatedPermissions`.

## 5. Approvals follow focus

When a `wait` request arrives and the session's terminal is frontmost (app match, plus the focused kitty window id when `kitten @ ls` can report it), Reef replies `{}` immediately and shows the card read-only. When a held request's terminal later becomes frontmost, Reef replies `{}` within the activation notification (measured ≈ 0.1 s).

## 6. Status-line shim (optional)

Claude Code has exactly one `statusLine` slot, so Reef claims it only when nobody else holds it.

**States.** `StatusLineState.of(command:)` reads `statusLine.command` from `~/.claude/settings.json` and reports:

| State | Meaning | What Reef does |
|---|---|---|
| `free` | no `statusLine` key | Settings offers Install |
| `ownedByReef` | command contains `/.reef/bin/reef-statusline` | Settings offers Remove |
| `ownedByOther(cmd)` | anything else | Writes nothing; Settings names `cmd` and the header falls back to the session count |

**What Install writes.** A shell script at `~/.reef/bin/reef-statusline` that execs `reef-bridge --task statusline-cache --cache-file ~/.reef/cache/rl.json`, plus the `statusLine` key pointing at it. Nothing else in the settings file is touched, and a timestamped backup is taken first.

**What the shim does.** It reads the status payload Claude Code sends on stdin, writes that payload's `rate_limits` object to the cache, and **prints nothing**. Claude Code renders a status-line command's stdout, so echoing the payload back would print raw session JSON under every prompt. An empty status line is the correct output for a shim whose only job is to observe. Malformed or missing input is ignored silently; the status line never fails because of Reef.

**What the app reads.** `UsageReader` polls the cache every 30 s. Staleness is measured from the cache file's modification time, so a reading older than 10 minutes renders grey rather than passing as live.

**Removing Reef.** Use Settings → Integrations → Remove before deleting the app. Deleting the app alone leaves `statusLine` pointing at a script that no longer exists, and Claude Code will show an empty status line until the key is removed by hand.

## 7. Transcript ingress (Codex, read-only)

Hooks are Reef's control channel. Codex also has front ends that never run them: the VS Code extension drives its own `codex app-server` binary, which ignores `~/.codex/hooks.json` entirely. For those, Reef reads what Codex writes to disk.

**Where.** `~/.codex/sessions/<YYYY>/<MM>/<DD>/rollout-*.jsonl`, one file per session, appended as the agent works. `CodexTranscriptWatcher` polls every 2 s, considers only files modified in the last 30 minutes, and reads each one forward from a stored byte offset. A trailing partial line is left unconsumed, so a record Codex is still writing is parsed whole on the next pass. Offsets live in memory; a relaunch re-folds the recent files.

**What is skipped.** The first complete line decides, and a file rejected once is never reopened:

| Rejected | Why |
|---|---|
| `thread_source` other than `user`, or any `parent_thread_id` | Codex writes a transcript per internal subagent. On this machine 1255 of 1316 October transcripts were `guardian_review` or `subagent` runs, which would bury the real work. |
| `originator` in `codex-tui`, `codex_cli`, `codex_exec` | Those front ends deliver Reef's hooks themselves. Reading their transcripts too would show the session twice, and would bring it back after its `SessionEnd` removed it. |
| Anything that is not a `session_meta` record with a non-empty `id` | Truncated, malformed, or a shape Reef does not know. |

An unknown originator is accepted: a new hookless front end is exactly the case this ingress exists for.

**Records that matter.** `event_msg/task_started` starts a turn, `task_complete` ends it, `thread_settings_applied` carries the model, and a `response_item` message with `role: assistant` is the closing message. Every other record type is ignored, so a Codex update that adds records degrades to missing detail rather than a broken session.

**Hooks win.** A transcript never overwrites a session that arrived through hooks, and a hook event takes over a session the watcher found first by flipping its ingress. Watched sessions carry no `PendingRequest` and so can never show approval buttons: a transcript records what happened, it cannot answer. Clicking one focuses VS Code.

**Announcing.** Only a completion that happens while Reef is watching reveals the panel and plays a sound. A session that had already finished when the watcher first read it joins the list silently, and a session whose transcript carries no turn yet shows idle rather than flashing done.

**Turning it off.** Settings → Integrations → "Watch Codex sessions from other editors". Off removes every watched session and stops the polling.
