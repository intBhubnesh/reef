# Reef Stage 2 — motion and presence

Date: 2026-10-31. Status: draft for approval. Follows `2026-10-28-reef-design.md` (Stage 1, shipped as v0.1.0).

## Intent

Stage 1 made Reef work. Stage 2 makes it feel alive. The user's words after using both: Vibe Island's "micro interaction and the agent on the notch doing action feel so engaging, and for each action they have separate interaction", while Reef's content is less well organised and every state change uses the same single spring.

Three things change:

1. **The agent on the notch is a character.** Its sprite animates continuously and differently per state, so a glance tells you whether an agent is thinking, blocked on you, or finished.
2. **Every event gets its own entrance.** A permission request arriving, a completion peek, a hover expand and a collapse are four different motions with different timings, not one spring reused.
3. **The panel is laid out like the reference.** A real header, measured spacing, chips and badges where the eye expects them.

## Why now

The teardown was done precisely to learn this layer, and it is the layer Stage 1 deliberately skipped. The measurements now exist: `_reference/vibe-island/motion/MOTION-SPEC.md` (19-row animation table derived from six screen recordings of real agent sessions) and `.../LAYOUT-SPEC.md` (pixel measurements of every element in the expanded panel). Those two files are the acceptance target for this stage.

## Goals

1. Per-state sprite animation at the measured cadence: a stepped 8-frame idle/working cycle at 150 ms per frame, an irregular eye jump plus a bobbing attention glyph while waiting on the user, and a slow blink plus a blinking cursor bar when done.
2. Distinct, measured transitions:
   - hover expand: 150 ms dwell, then width and height on one spring (response 0.35, damping 0.78, ~1.3 % overshoot), with a 1.02 pill scale on pointer-enter;
   - request arrival: pill content swaps instantly to the attention state, then auto-expands within ~50 ms;
   - resolution and peek collapse: a critically damped spring (response 0.45, damping 1.0, no overshoot);
   - completion peek: auto-expand ~1.1 s after the collapse, hold exactly 5 s, restart the hold when the pointer leaves;
   - content growth while open: snap, no animation.
3. Matched geometry transitions: the pill's sprite group and count ride to their panel positions rather than cross-fading, using SwiftUI `matchedGeometryEffect`.
4. Staged content reveal: header text fades in at ~150 ms over 120 ms, session rows at ~120 ms over 170 ms with a ≤5 pt downward drift.
5. Panel layout to the measured spec: 648 pt wide, 36 pt header band, 640 pt content column, 16 pt block rhythm, 18 pt text leading, the measured chip, badge, subagent-box and completion-card metrics, and Reef's palette re-derived from the measured one.
6. A usage header: Claude 5 h and 7 d limits and the active model, read from the status-line cache the way the teardown documents, with a graceful "no data" state.
7. `prefers-reduced-motion` support: all stepped animation stops, springs become short fades, nothing else changes.

## Non-goals (this stage)

- iPhone push, SSH remote, more agents, custom jump rules, sound packs, licensing (Stage 3 or never, per the Stage 1 design).
- Session switcher, quiet hours, follow-up reminders, context menus (deferred Stage 2 items from the original list; they are behaviour, not motion, and would double this stage).
- Codex usage figures (the installed Codex cannot run its model; Claude usage only for now, with the provider abstraction in place).

## Anti-goals

- **Copying their artwork.** The sprite pixel art is not reproduced: the recordings never resolved it, and it is their design. Reef keeps its own 5×5 glyphs and gives them the measured *behaviour* (frame cadence, bob period, blink rhythm). Same for the app icon and sounds. What is matched is geometry, timing and information architecture, which is what makes the app feel right.
- **Animation that fights the user.** Nothing may delay a decision: the approval buttons must be hit-testable the moment the panel starts expanding, and no transition may swallow a click.
- **Per-frame work on the main thread.** A 150 ms stepped sprite must not re-render the whole panel. Animation state lives in small leaf views driven by `TimelineView`, never in `AppState`.

## Constraints

- Everything from the Stage 1 design still holds: macOS 14+, SwiftPM only, no third-party packages, ad hoc signing, `~/.reef` paths, the socket protocol in `docs/protocol.md`.
- Pure animation logic (phase selection, timing curves, reveal scheduling) goes in `ReefCore` so it is testable without a screen. Only the rendering lives in `ReefApp`.
- The measured numbers are the contract: they live in one `Motion` namespace as named constants, with the spec row cited in a comment, so a future change is traceable to a measurement.
- No regression in Stage 1 acceptance: all 14 items plus the review fixes must still hold.

## Decided: how it works

### 1. `Motion` constants (ReefCore)

One file, `Sources/ReefCore/Motion/Motion.swift`, holding every measured value as a named static: `hoverDwell = 0.15`, `expandResponse = 0.35`, `expandDamping = 0.78`, `collapseResponse = 0.45`, `collapseDamping = 1.0`, `peekHold = 5.0`, `peekDelay = 1.1`, `requestExpandDelay = 0.05`, `pillHoverScale = 1.02`, `headerFadeDelay = 0.15`, `headerFadeDuration = 0.12`, `rowFadeDelay = 0.12`, `rowFadeDuration = 0.17`, `rowDrift = 5`, `spriteFramePeriod = 0.15`, `spriteCycleFrames = 8`, `bobUp = 0.30`, `bobDown = 0.58`, `blinkClosed = 0.30`, `blinkPeriod = 2.4`, `cursorOn = 0.78`, `cursorOff = 0.45`. Each carries a comment naming its MOTION-SPEC row.

### 2. Sprite animator (ReefCore, pure)

`SpriteAnimator` turns `(SessionStatus, elapsed: TimeInterval)` into a `SpriteFrame { bodyFrame: Int, eyesOpen: Bool, glyph: Glyph?, glyphOffset: Int, cursorOn: Bool }`.

- `.idle`, `.working`, `.runningTool`, `.compacting` → `bodyFrame = Int(elapsed / 0.15) % 8`; the body changes every 4th step, the eyes every step (MOTION rows 12, 13).
- `.waitingForApproval/Question/Plan` → eyes step on a deterministic pseudo-random schedule with a median 200 ms gap (seeded by the request id so two waiting sessions do not animate in lockstep); `glyph = .question`, `glyphOffset` alternating 0/1 cell with 300 ms up and 580 ms down (rows 14, 15).
- `.done` → eyes closed for 300 ms every 2.4 s; `glyph = .cursor`, `cursorOn` 780 ms on / 450 ms off (rows 16, 17).
- `.failed` → eyes closed, no glyph, static (no measurement exists; stated as a Reef choice).
- Reduced motion → frame 0, eyes open, glyph present but static.

Pure function of `(status, elapsed, seed)`, so the whole table is unit-testable.

### 3. Transition kinds (ReefCore)

`NotchTransition` enumerates `hoverExpand, requestExpand, peekExpand, collapse, snap` and maps each to `(delay, response, damping)`. `NotchMachine` gains `lastTransition: NotchTransition` so the view knows which spring to apply to the current state change, replacing the single hard-coded spring in `NotchHostView`. The machine's existing states and intents do not change; `peekHold` replaces the settings-driven `revealDwell` default of 5 s (the setting stays, defaulting to the measured value), and a pointer-leave during a peek restarts the hold (MOTION row 9).

### 4. Panel layout (ReefApp)

`Theme` is rewritten from LAYOUT-SPEC: surfaces `#000000` panel, `#111111` completion card, `#141414` subagent box, `#1A1A1A` paywall-equivalent, `#1C1C1E` header highlight, `#2C2C2E` chips, borders `#2A2A2A`; text `#F2F2F2` / `#E5E5EA` / `#9A9A9E` / `#8E8E93`; accents green `#30D158`, waiting orange `#F59E3A`, blue `#4A8CFF`, Claude chip `#3A2A22` on `#D9876A`, Codex chip `#1F3A5A` on `#6FA8FF`. Metrics: panel 648 pt wide with a 36 pt header band, 640 pt content column, 16 pt between blocks, 18 pt leading, 10 pt card radius, 24 pt panel bottom radius, 11 pt pill bottom radius, chips 15 pt tall with 6.5 pt gaps and a 21 pt right inset, sprite 20×15 pt in rows and 16 pt in the pill, text column at 69.5 pt.

`HeaderRow` becomes the measured usage header: left `✳ 5h NN% H:MM | 7d NN% Dd` in a monospaced bold face with green percents and grey times, right the model name with its percentage, then mute and gear at 13 and 14 pt, 30 pt apart. With no usage data it shows the session count as today.

`SessionCardView` is re-laid out to the measured row: sprite plus action glyph on the left, title line (`project · prompt title`), `You:` line, summary line, chips and status dot right-aligned, jump affordance chip. The subagent box and completion card take their measured backgrounds, paddings and typography, and the completion body renders real Markdown (fixing a deferred Stage 1 minor: block-level Markdown instead of inline-only).

### 5. Usage provider (ReefCore + ReefApp)

`UsageProvider` protocol with a `ClaudeStatusLineUsage` implementation: Reef installs a status-line shim at `~/.reef/bin/reef-statusline` exactly as the teardown documents for the original (the agent pipes its status-line JSON in, the shim writes `rate_limits` to `~/.reef/cache/rl.json`), and the app reads that cache. Installation is opt-in from Settings → Integrations with a clear explanation, because it writes `statusLine` into the agent's settings file; declining leaves the header showing the session count. Parsing (`{five_hour: {used_percentage, resets_at}, seven_day: {...}}` → `UsageSnapshot`) lives in core and is unit-tested; staleness over 10 minutes renders grey.

### 6. Reduced motion and performance

`AnimationSettings.reduceMotion` reads `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` and is observed. When set: `SpriteAnimator` returns the static frame, transitions become 120 ms fades, the pill hover scale is skipped. `TimelineView(.periodic(by: 0.15))` drives only the sprite leaf view; when every visible session is idle and the panel is collapsed, the schedule drops to `.animation(minimumInterval: 0.15, paused: true)` so an idle Reef does no per-frame work.

## Calls made after the builder check

1. **Where the motion lives.** The `NSPanel` is sized once per state to the target panel rect plus 24 pt of overshoot headroom, and never animated itself; the spring runs on the drawn shape inside SwiftUI. Expanding sizes the window first, then animates the shape; collapsing animates the shape, then shrinks the window after the full measured collapse duration plus 100 ms (the current hard-coded 0.3 s is shorter than the measured tail and clips it). `MouseMonitor` must hit-test the drawn panel rect, not the oversized window, or the peek-restart rule cannot work.
2. **Idle animates.** The reference shows no idle/working difference, and a frozen agent defeats the stage. Acceptance 12 is rewritten: *Reef with no visible sessions* does no per-frame work; one idle session animates.
3. **One character, agent identity in the chip.** Reef gets a single original character glyph (its own design, roughly 8×6 cells at 2.5 pt to fill the measured 20×15 pt) with eye cells and body cells, shared by both agents. Agent identity moves entirely to the coloured chip and the tint. Stage 1's two 5×5 patterns are retired.
4. **Status-line shim: install only when the slot is free.** If Claude Code's settings already define a `statusLine` (Vibe Island owns it on this machine), Reef does not touch it: Settings shows "another app owns the status line" and the header falls back to the session count. No chaining, no snippet insertion in this stage. See the open question below.
5. **Model block deferred.** The documented cache carries only the 5 h and 7 d windows. The right-hand model block is not built this stage; the space is left for it. `HookEvent`/`Session` do gain a `model` field (one line each, with a reducer test) so a later stage has it.
6. **Approval, question and plan cards keep their Stage 1 structure**, re-tinted by the new `Theme` and re-spaced to the 16 pt block rhythm and 18 pt leading. LAYOUT-SPEC never measured them, so there is nothing to match; re-designing them is out of scope.
7. **The notice becomes a banner card** using the measured banner metrics (623.5×61.5 pt, 10 pt radius, warm surface, icon circle, title plus body), which is also what Stage 1 acceptance 13 needs. Reef has no paywall or licence footer, so the measured bottom rhythm ends after the last card with the measured 20 pt inset.
8. **Phase origins are per session.** `Session` gains `statusChangedAt`, set by the reducer whenever `status` changes (with a test). `SpriteAnimator` takes elapsed-since-that plus a seed derived from the session key, so sessions animate out of phase and the cursor bar can start 750 ms after a peek.
9. **Reveal timings per transition.** `hoverExpand` uses the 150/120 ms header and 120/170 ms row pairs; `requestExpand` and `peekExpand` use 0/50 ms for both, as measured.
10. **Status to colour**: blue `#4A8CFF` idle and working, orange `#F59E3A` waiting on the user, green `#30D158` done, red `#FF5B5B` failed. Where the two measurement files disagree (panel bottom radius 24 vs 40 pt, pill radius 11 vs 22 pt), the builder re-measures once against `screenshots/island-expanded.png` and `screenshots/collapsed.png` in the first task and records the result in `Motion`.

## Left to the builder

- The exact pixel patterns of Reef's own 5×5 glyphs per frame (idle cycle, question mark, cursor bar), as long as the cadence matches.
- Whether the matched-geometry transition uses one namespace per element group or a single shared one.
- How to fake a usage snapshot in previews and tests.
- Whether the header's monospaced numerals use the system monospaced face or the bundled Departure Mono (which Stage 1 fetches but does not use; either is acceptable, bundling it resolves another deferred minor).

## Acceptance

1. With one agent working, the sprite steps through 8 frames at 150 ms and the body changes every 4th step; with `prefers-reduced-motion` on, it is static.
2. A waiting session shows the orange glyph bobbing at the measured 300/580 ms, with its eyes jumping irregularly; two waiting sessions are visibly out of phase.
3. A finished session blinks every 2.4 s with a cursor glyph at 780/450 ms.
4. Hovering the pill scales it immediately, then expands after 150 ms with visible overshoot; leaving collapses it without overshoot.
5. A permission request swaps the pill instantly and expands within ~50 ms; the Allow button is clickable while the panel is still growing.
6. A completion peek appears ~1.1 s after the prior collapse, holds 5 s, and restarts its hold if the pointer enters and leaves.
7. Growing content while the panel is open snaps without a spring.
8. The expanded panel matches LAYOUT-SPEC within ±2 pt for panel width, header height, content column, chip sizes and the subagent box, verified by measuring a screenshot.
9. The header shows Claude 5 h and 7 d percentages after the status-line shim is installed, grey when stale, and the session count when the shim is absent.
10. Completion and plan cards render Markdown headings and bullets as formatting, not literal characters.
11. All Stage 1 acceptance items still pass; `swift test` is green with the new core tests.
12. Reef with no visible sessions and the panel collapsed uses no measurable CPU over a 60 s sample; one idle session animates.
13. A completion peek stays open while the pointer is inside the panel and restarts its 5 s hold when the pointer leaves.
14. The notice from a hook self-heal appears as a banner card at the top of the panel (Stage 1 acceptance 13 still passes).
