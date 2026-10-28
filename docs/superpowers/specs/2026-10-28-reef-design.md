# Reef — design

Date: 2026-10-28. Status: draft for approval.
Working name "Reef" is my call; rename freely (it only affects the bundle id, the `~/.reef` directory and the hook `--source` label is per agent, not per app).

## Intent

A macOS notch app, in the spirit of Vibe Island, that watches the user's AI coding agents and makes two moments impossible to miss: **an agent needs my input** (a permission request or a question) and **an agent finished**. The user can approve or deny the request from the notch itself, seeing what the agent wants to do (the command, the diff, the file), and can click any session to jump to the terminal it runs in.

Why: the user runs Claude Code and Codex in terminals all day and loses time noticing when an agent is blocked on them. Vibe Island solves this but is closed source and paid for exactly this part (jump, approvals, shortcuts are behind a $14.99 unlock). The reverse-engineering teardown in this folder (`vibe-island-spec.md`, `vibe-island-ui-observed.md`) is the reference for both the interface and the mechanism.

## Goals

1. Show every live Claude Code and Codex session in the notch pill, with a per-session status.
2. When an agent asks permission, expand the panel automatically, render the request (tool, command or diff), and let the user Allow / Deny / Always allow from the panel. The decision is returned to the agent through its hook protocol.
3. When an agent asks a question (Claude Code `AskUserQuestion`, Codex questions), render the options and let the user answer from the panel.
4. When an agent finishes a turn, reveal a short completion card with the last assistant message, then auto-collapse.
5. Clicking a session jumps to its terminal: kitty and Ghostty natively (the user's terminals), VS Code window focus, with a plain "activate app" fallback.
6. Feel like the original: hover-to-expand with a dwell, auto-collapse on mouse leave, black pill hugging the notch, pixel-art agent sprites, dark panel, spring animations.

## Feature parity target (from the Vibe Island changelog, 1.0.0 → 1.0.55)

The user wants "pretty much similar" to Vibe Island. Parity is staged; the stage number is the delivery order.

**Stage 1 — the notch and the two moments (this design).** Pill with per-session sprites and count; hover/click expand with dwell; auto-collapse; session cards (project, worktree/branch, last prompt, tool line, agent and terminal chips, elapsed time); approval cards with Bash / diff / file / generic renderers and Allow / Deny / Always allow; parallel approval queue (several pending requests stack, oldest first); AskUserQuestion wizard (single, multi, custom answer); plan-review card (Claude Code `ExitPlanMode`: Approve / Deny with feedback); completion card rendering Markdown; failure card; subagent list with nesting; keyboard shortcuts for approvals and jump; quick mute; three built-in sounds; kitty, Ghostty, VS Code and tmux jump; Settings (General, Integrations, Notifications, Display, Shortcuts, About); hook self-healing (re-add entries if removed, with a notice).

**Stage 2 — comfort.** Auto-hide when idle with fade; smart suppression; quiet hours; follow-focus display selection; session switcher (`⌃G` cycles sessions while expanded); right-click context menu on cards (jump, archive, copy session id); follow-up reminders (1/2/3/5 min) when a request stays unanswered; idle reminder; system notification "All agents finished"; custom sound files and Apple system sounds picker; Launch at login; bypass-permissions pill (shows when the agent runs with permissions bypassed); model and reasoning-effort chips; git worktree detection; Display tab with notch width/height tuning and live preview; compact question mode; silence rules (per-directory and first-prompt filters).

**Stage 3 — reach.** More agents through the same bridge (Gemini CLI, Cursor Agent, OpenCode, Copilot CLI, Kimi, custom agents with a manifest file and `--source` name rules exactly as Vibe Island documents them); custom jump rules (`~/.reef/integrations/<app>.json` with `bundleIdentifier` and a `urlScheme` template using the same variable names); iTerm2, Terminal.app, Warp, WezTerm, Zed and Cursor jumps; usage-limit header (Claude 5h/7d via the status-line cache trick, Codex rate limits); iPhone push through Bark with AES-GCM; SSH Remote; localisation.

Explicitly never: licensing, trials, device limits, analytics, crash telemetry, anti-tamper, community panels, edition cards.

## Non-goals (first version)

- Licensing, trials, analytics, crash reporting, Sparkle updates, iPhone/Bark push, SSH Remote, sound packs and registry, usage-limit tracking, custom-agent manifests, Mac App Store edition, localisation beyond English.
- Agents other than Claude Code and Codex. The bridge keeps `--source <name>` so more can be added later.
- A menu-bar icon. The app is `LSUIElement`; Settings opens from the gear in the expanded panel.

## Anti-goals

- Silently losing a permission request. If the app cannot render it, the bridge must fall through so the agent's own terminal prompt still appears. A hook that hangs or returns garbage would freeze the user's agent; that is the worst failure.
- Fighting the other notch apps on this Mac. boringNotch, OpenIsland and Vibe Island all have hooks installed in `~/.claude/settings.json` and `~/.codex/hooks.json`. Reef's installer adds its own entries and never removes others. The user is expected to disable the others while using Reef, because Claude Code takes the first hook that returns a decision.
- Shipping the original's assets. The extracted files in `assets/` (icons, app icon, onboarding wallpaper, ceremony sound, pixel cursor) are reference material only. Reef draws its own sprites and app icon, synthesises its own sounds, uses Departure Mono from its upstream OFL release, and uses the official Anthropic and OpenAI marks for agent chips. The original's exact dimensions, spacing, colours and behaviour (documented in `vibe-island-ui-observed.md`) are fair to match.

## Constraints

- macOS 14+, Apple Silicon and Intel. Swift 5.10+, SwiftUI for views, AppKit for the window layer. Xcode project generated from a Swift Package via `xcodegen` or plain SwiftPM executable target plus a bundling script (builder's choice, see below).
- No third-party runtime dependencies except what is needed for the diff view (builder may use a small Swift diff library or write a line diff).
- Hook commands must return within the agent's timeout. Non-blocking events are fire-and-forget with a 2 s cap. Blocking events (PermissionRequest, question) wait up to 1 h and must return a valid "no decision" JSON on any failure, so the agent falls back to its terminal prompt.
- Everything lives under `~/.reef/` (bin, run, cache) and `~/Library/Application Support/Reef/` (settings, session-to-terminal map), log at `~/Library/Logs/Reef/reef.log` as JSON lines.

## Decided: how it works

### 1. Hook installer (in-app, Settings → Integrations, plus `reef-bridge install`)

- Claude Code: adds entries to `~/.claude/settings.json` under `hooks` for `SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest, Notification, Stop, StopFailure, SubagentStart, SubagentStop, SessionEnd`. Each entry is `{"matcher":"*","hooks":[{"type":"command","command":"/bin/sh -c '[ -x \"$HOME/.reef/bin/reef-bridge\" ] && \"$HOME/.reef/bin/reef-bridge\" --source claude; exit 0'","timeout":N}]}` with `timeout` 3600 for `PermissionRequest`, 5 for the rest. Timestamped backup before every write. Idempotent: detects its own entries by the `~/.reef/bin/reef-bridge` substring.
- Codex: same shape in `~/.codex/hooks.json` with `--source codex`, matchers as Codex expects (`startup|resume|clear` for SessionStart, `manual|auto` for compaction). Codex requires a trust hash per hook in `config.toml` `[hooks.state]`; Reef writes the `trusted_hash = "sha256:<hash of command string>"` entries the same way Vibe Island does (observed on this machine). If Codex changes the hash recipe, Reef shows "hook not trusted" in Settings with the fix command rather than guessing.
- Questions and plans (verified against the Claude Code 2.1.267 hooks reference, saved at `evidence/claude-hooks.md`): `AskUserQuestion` and `ExitPlanMode` are tools that go through the normal permission flow, so Reef handles them in the `PermissionRequest` hook. For `AskUserQuestion` the allow decision must carry `updatedInput` = the original `questions` array plus an `answers` object mapping each question text to the chosen label (multi-select labels joined with commas). For `ExitPlanMode` the allow decision echoes `updatedInput` with the injected `plan` and `planFilePath`; a deny carries the user's feedback in `message`. The `Notification` hook with `notification_type == "permission_prompt"` fires only after a prompt has waited about six seconds; Reef uses it as a fallback signal, never as the primary one.

### 2. Bridge (`~/.reef/bin/reef-bridge`, Swift command-line executable, no AppKit)

- Reads stdin JSON, adds `source`, `tty` (from `/dev/fd/0..2` via `ttyname`, else `ps -o tty= -p $PPID`), `ppid`, `pid`, and a selected environment subset: `TERM_PROGRAM, TERM_SESSION_ID, ITERM_SESSION_ID, KITTY_WINDOW_ID, KITTY_PID, GHOSTTY_RESOURCES_DIR, TMUX, TMUX_PANE, VSCODE_PID, __CFBundleIdentifier`. Adds `git` `{root, branch, worktree}` for `cwd` cached by path hash.
- Connects to `~/.reef/run/reef.sock` (Unix domain, SOCK_STREAM). Framing: one JSON object per line, newline terminated, UTF-8. Request `{"v":1,"id":"<uuid>","mode":"fire|ack|wait","event":{...}}`. Response `{"v":1,"id":"<same>","reply":{...}}` or nothing for `fire`.
- Mode by event: `PermissionRequest` → `wait`; everything else → `fire`.
- Output on stdout: for `wait`, the agent-specific decision JSON (below); for everything else `{}`. Exit code always 0. Any error (socket missing, app not running, timeout, bad JSON) → print the no-decision JSON and exit 0.
- Claude Code decision JSON (verified): `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`; deny is `{"behavior":"deny","message":"Denied from Reef"}`. "Always allow" is allow plus `"updatedPermissions":[{"type":"addRules","behavior":"allow","destination":"session","rules":[{"toolName":"<tool>","ruleContent":"<content>"}]}]`, where Reef echoes one of the `permission_suggestions` entries Claude Code sent in the request input when present (that is exactly what the terminal's "always allow" option does), otherwise a whole-tool rule. No decision → `{}` (exit 0), which leaves the terminal prompt in charge.
- Codex decision JSON (verified against the Codex hooks reference for 0.140, saved at `evidence/codex-hooks.md`): identical shape, `hookSpecificOutput.decision.{behavior: allow|deny, message}`. Codex has no `updatedPermissions`, so "Always allow" is plain allow for Codex. Common stdin fields: `session_id, transcript_path, cwd, hook_event_name, model, permission_mode, turn_id`. Supported events: `SessionStart, SessionEnd, UserPromptSubmit, PreToolUse, PermissionRequest, PostToolUse, PreCompact, PostCompact, SubagentStart, SubagentStop, Stop, Interrupt`. `SessionEnd` and `Interrupt` hooks must finish within 1 s. Hook trust: the docs say Codex keeps a hash registry and the user trusts hooks through `/hooks`; on this machine the registry is visible as `[hooks.state]` entries in `~/.codex/config.toml`. Reef writes hooks.json only, then shows "run `/hooks` in Codex and trust the Reef entries" in Settings with a live trusted/untrusted indicator read from `[hooks.state]`.
- Also ships `reef-bridge install|uninstall|status` for the hook files, so the app and a terminal user share one implementation.

### 3. App core

- `SocketServer`: listens on `~/.reef/run/reef.sock` (recreated at launch, 0600). Parses lines, dispatches to `SessionStore` on the main actor, keeps `wait` connections open in a `PendingRequests` table keyed by request id with a deadline; a UI decision writes the reply and closes. On app quit, every pending request is answered "no decision".
- `SessionStore` (`@Observable`): `Session {id, source, cwd, project, branch, terminal identity, startedAt, lastEventAt, status, lastPrompt, lastAssistantMessage, currentTool, subagents[], pending: PendingRequest?}`. Status reducer: `SessionStart→idle`, `UserPromptSubmit→working`, `PreToolUse→runningTool(name)`, `PermissionRequest→waitingForApproval`, `Notification(permission_prompt)→waitingForApproval` (if no live request, read-only), `Stop→done (reveal)`, `StopFailure→failed`, `SessionEnd→removed`, idle sessions removed after 2 h (setting). Persists `session id → terminal identity` to `session-terminals.json` so a jump still works after relaunch.
- `NotchController`: state machine `closed, peek(badge), transient(kind, until), blocking(requestId), manualExpanded`. Intents: `hoverExpand, hoverLeave, click, permission, question, taskComplete, collapse, escape`. Rules: a `blocking` state is never auto-collapsed; `transient` collapses after the reveal dwell (5 s default) or on mouse leave after 1 s; hover expand needs a dwell (0.15 s default) and is suppressed while the frontmost app is the terminal of the only session (smart suppression, setting).

### 4. Window layer

- One borderless `NSPanel` per screen with a notch (only the main screen in v1): `level = .statusBar + 1` (observed layer 27 on the original), `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, no shadow, clear background, `ignoresMouseEvents` toggled so only the island shape is hit-testable when collapsed. Frame 680×580 pt centred on the notch (settings: max width, max height).
- Geometry from `NSScreen.safeAreaInsets.top` and `auxiliaryTopLeftArea/auxiliaryTopRightArea`: notch width = screen width − left aux width − right aux width; height = safe top. Collapsed pill = notch width + 32 pt each side (so ~249 pt on a 14-inch), height = safe top (33 pt), bottom corners radius 16. External screen without a notch: synthetic 185×33 island at top centre.
- Global `NSEvent` monitors for `.mouseMoved` (hover), `.leftMouseDown` outside the panel (collapse unless blocking), `ESC` collapses. Hover must work with real mouse input; synthetic events are not a requirement.

### 5. Views (SwiftUI, dark only, matching the teardown)

- **Pill**: black, sprites on the left (one per session, 5×5 pixel glyph per agent: Claude = sparkle, Codex = grid; animated 2-frame blink when working, solid when idle, orange when waiting on the user, green flash on done), session count on the right. A waiting session also shows a small amber dot on the right.
- **Expanded panel**: black, 24 pt radius, width ≤ 648 pt. Header row: left = usage area reserved but empty in v1 (shows project count instead), right = speaker (mute toggle), gear (Settings). Then one **session card** per session: sprite, `project · last prompt title`, `You: <last prompt>`, current tool line, chips `Claude|Codex`, terminal name, age. Subagents box when present. Cards are clickable → jump.
- **Approval card** (replaces the session card body while pending): tool name badge; renderer per tool: `Bash` → command in monospace with description; `Edit/Write/MultiEdit` and Codex `apply_patch` → unified line diff with add/remove colouring, file path header; `Read/Glob/Grep/WebFetch/WebSearch` → one-line summary; anything else → pretty JSON, collapsed past 12 lines. Buttons: **Deny** (secondary), **Allow** (primary), **Always allow** (text button). Keyboard while expanded: `⌃Y` allow, `⌃N` deny, `⌃A` always, `⌃T` jump, `esc` collapse.
- **Question card**: question text, option buttons (single or multi select), free-text field when the agent allows it, Submit.
- **Completion reveal**: card with "Done" tick, last assistant message (3 lines, expandable), elapsed time; auto-collapses after the reveal dwell.
- **Settings window** (SwiftUI `Settings` scene, 620×680, sidebar): General (launch at login, hover expand + duration slider, smart suppression, auto-collapse, reveal dwell, idle cleanup), Integrations (Claude Code / Codex install status and buttons, trust status for Codex), Notifications (sound on/off per event: input needed, done, failed; system notification when "All agents finished"), Display (panel max width/height, show project, show branch, show subagents), Shortcuts (read-only list in v1), About.
- Sounds: three short built-in sounds synthesised at build time or bundled as small AIFF (input needed, done, failed). No packs.

### 6. Jump engine

Ordered steps per session, first success wins; each step logs its outcome:
1. `kitty`: if `KITTY_WINDOW_ID` and `KITTY_PID` present and `kitty @ --to unix:<socket>` is reachable (`allow_remote_control` set), run `kitten @ focus-window --match id:<id>`; else activate kitty.app.
2. `ghostty`: Ghostty has no remote control; use the OSC 2 title marker trick: the bridge writes `\e]2;reef:<session-id>\a` to the tty on SessionStart, then the jump uses Accessibility (AXUIElement) to find the Ghostty window/tab whose title contains the marker and raises it. Requires the Accessibility permission; prompt once.
3. `vscode`: if `VSCODE_PID` / `__CFBundleIdentifier == com.microsoft.VSCode`, activate VS Code and run `code --reuse-window <cwd>`.
4. `tmux`: if `TMUX_PANE` present, after focusing the terminal run `tmux select-window -t <pane>` and `tmux select-pane -t <pane>`.
5. Fallback: `NSRunningApplication.activate` for the bundle id captured at session start.
Apple Events usage string and the `com.apple.security.automation.apple-events` entitlement are included even though v1 does not script iTerm2/Terminal, so adding them later needs no re-signing change.

### 7. Project layout

```
reef/
  Package.swift                 # targets: ReefBridge (exe), ReefCore (lib: protocol, models, reducer), ReefApp (exe, AppKit/SwiftUI)
  Sources/ReefBridge/           # stdin → socket → stdout
  Sources/ReefCore/             # Event, Session, Reducer, Protocol, Jump plan (pure, testable)
  Sources/ReefApp/              # App, NotchPanel, views, Settings, SocketServer, JumpEngine, Sounds
  Tests/ReefCoreTests/          # reducer, protocol framing, decision JSON, jump planning
  scripts/bundle.sh             # builds Reef.app, copies reef-bridge into Contents/Helpers, codesigns ad hoc
  docs/protocol.md              # hook events, socket framing, decision JSON per agent (kept current)
  docs/superpowers/specs/2026-10-28-reef-design.md  # this document
```
Repo at `~/Code/reef` (new git repo), my call.

## Calls made after the builder check (mine unless marked)

1. **v1 = Stage 1.** The acceptance list below is extended to cover it. Duplicates resolved: launch at login is Stage 1 (General tab); smart suppression moves to Stage 2.
2. **Approvals follow focus.** While a `PermissionRequest` hook is pending, the agent's terminal shows nothing, so a long hold would look like a freeze. Rule: if the session's terminal window is frontmost when the request arrives, the bridge returns no decision immediately and the panel shows a read-only "waiting in terminal" card. Otherwise Reef holds the request and expands the panel; the moment the user focuses that terminal window (app activation + tty match), Reef releases it with no decision so the terminal prompt takes over. Hold cap stays 1 h. Smart suppression therefore never hides an approval.
3. **Sessions without a terminal** (no tty and no known host app: `claude -p`, SDK runs, probes) are not shown in the pill or counted; a Display toggle "Show headless sessions" lists them in the panel without a jump affordance.
4. **Always allow** echoes one of Claude Code's own `permission_suggestions` with `destination: "session"`; with no suggestion it adds a whole-tool rule at session scope. Reef never writes to `.claude/settings*.json` for permissions. The button is hidden for Codex.
5. **Ghostty titles.** Reef's installer sets `env.CLAUDE_CODE_DISABLE_TERMINAL_TITLE = "1"` in `~/.claude/settings.json` (disclosed in Integrations with an undo button; it is already set on this machine by Vibe Island). The bridge writes a readable title `<project> · reef:<8-char id>` on SessionStart and UserPromptSubmit; the marker suffix is what the jump matches.
6. **Signing**: no code-signing identity exists on this Mac. Until one is added, builds are ad hoc signed with a stable bundle id; the Accessibility grant for the Ghostty jump may need re-granting after rebuilds (Reef shows a notice), and launch at login is best-effort. User's decision (2026-10-28): no certificate for now, will add one later. Build ad hoc; keep `CODE_SIGN_IDENTITY` a single variable in `scripts/bundle.sh` so the switch is one line.

## Left to the builder

- Spring curves, exact paddings, sprite pixel art.
- Whether to use xcodegen or a SwiftPM-only bundle script, as long as `scripts/bundle.sh` produces a runnable `Reef.app` with `LSUIElement`, usage strings and the Apple Events entitlement.
- Diff algorithm choice.
- How to unit-test the socket server (in-process client is fine).
- Log rotation.

## Acceptance (what "done" means for v1)

1. With Reef running and hooks installed, starting `claude` in kitty shows a sprite in the pill within 1 s.
2. Running a command that needs permission expands the panel with the command shown; pressing Allow lets Claude continue, Deny makes Claude report the denial; a request answered by neither within 1 h falls back to the terminal prompt.
3. Same for `codex` with an `apply_patch` approval showing a diff (or read-only with Jump if Codex decision output could not be verified, with that limitation stated in Settings).
4. When the turn ends, the panel reveals the completion card, plays the done sound, and collapses after 5 s.
5. Clicking the session card focuses the correct kitty window; in Ghostty it raises the right tab; in VS Code it focuses the window.
6. Quitting Reef while a request is pending does not hang the agent.
7. `swift test` passes for the reducer, framing and decision-JSON tests.
8. An `AskUserQuestion` from Claude Code shows the question card; choosing an option answers it in the terminal session without the user touching the terminal.
9. An `ExitPlanMode` request shows the plan; Approve continues, Deny with feedback sends the feedback to Claude.
10. Two sessions requesting permission at once show both cards, oldest first, and each resolves independently.
11. When the session's terminal is frontmost, the request is released to the terminal within 200 ms and the panel shows the read-only card.
12. `⌃Y`, `⌃N`, `⌃A`, `⌃T` and `esc` work while the panel is expanded; the mute toggle silences all three sounds.
13. Removing Reef's hook entries from `~/.claude/settings.json` while Reef runs restores them within 5 s and shows a notice.
14. Settings has General, Integrations, Notifications, Display, Shortcuts and About, and every control in General and Integrations is live.
