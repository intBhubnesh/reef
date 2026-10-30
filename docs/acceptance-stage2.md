# Reef Stage 2 acceptance — 2026-10-31

Run on a 14-inch MacBook Pro (macOS 26, Apple Silicon) with Claude Code 2.1.267, kitty, `dist/Reef.app` built by `scripts/bundle.sh` (universal, ad hoc signed). Vibe Island quit for the measurements. Contract: `_reference/vibe-island/motion/MOTION-SPEC.md` (`M<n>`) and `.../LAYOUT-SPEC.md` (`L<n>`). Suite: 143 tests, 0 failures.

## Stage 2 criteria

| # | Criterion | Result | Evidence |
|---|---|---|---|
| 1 | Working sprite steps 8 frames at 150 ms, body every 4th; static under reduced motion | PASS | On-screen change gaps measured from a 40 fps recording: median **150 ms** (`t6b.mov`). Cycle, body cadence and the reduced-motion freeze are covered by `SpriteAnimatorTests` (10 tests). |
| 2 | Waiting glyph bobs 300/580 ms, eyes jump irregularly, two sessions out of phase | PASS | `testWaitingBobsAtTheMeasuredPeriod`, `testTwoSeedsBlinkOutOfPhase`, `testWaitingEyeScheduleIsDeterministicAndBounded`; orange glyph visible in `t6-waiting.png`. |
| 3 | Done blinks every 2.4 s with a cursor glyph at 780/450 ms | PASS | `testDoneBlinkAndCursor` pins both phases including the 750 ms first-on. |
| 4 | Hover scales the pill, expands after 150 ms with overshoot; collapse without overshoot | PASS | Expansion began **130 ms** after the pointer settled; peak 654 pt against a final 648 pt = **+0.9 %** overshoot (target +1.3 %). Collapse peak never exceeded its starting width. |
| 5 | A request swaps the pill instantly and expands ~50 ms later; Allow is clickable during the expansion | PASS | Request auto-expanded without hover. Allow clicked **120 ms** into an expansion returned `{"behavior":"allow"}` to the waiting hook. |
| 6 | Completion peek ~1.1 s after the collapse, holds 5 s, restarts the hold on pointer-leave | PASS (unit) | `testHoverSuspendsACompletionPeekAndRestartsTheHold` and `testFailurePeekAlsoSuspendsOnHover` pin the machine. Not timed end-to-end on screen. |
| 7 | Content growth while open snaps | PASS (unit) | `.snap` carries a zero response; `testTransitionCurves`. Not timed on screen. |
| 8 | Panel matches LAYOUT within ±2 pt | PASS | Window frames read from CGWindowList: collapsed **249 × 33 pt** (L8: 249 × 33); expanded window **696 × 604** = panel **648 × 580** plus exactly the 24 pt overshoot headroom per side (L1: 648 wide). |
| 9 | Usage header shows 5 h and 7 d, greys when stale, falls back when absent | PASS | Live: `5h 21% 3h8m │ 7d 28% 5d12h` with the measured colours (`t8-usage.png`). Stale (file older than 10 min): all grey (`t8-stale.png`). Cache deleted: "2 sessions" (`t8-absent.png`). |
| 10 | Plan and completion cards render Markdown as formatting | PASS | First attempt flattened every block onto one line; replaced with Reef's own block renderer. Plan now shows a bold heading, a real numbered list, inline code in monospace and a separate risk paragraph (`t9-md3.png`). `MarkdownBlocksTests` (6 tests). |
| 11 | Stage 1 acceptance still passes; `swift test` green | PASS | 143 tests, 0 failures. Stage 1 items re-checked below. |
| 12 | No visible sessions → no measurable CPU; one idle session animates | PASS, with a cost to note | Warm, no sessions, 60 s: **mean 0.12 %**, median 0.10 %, max 0.40 %. One idle session, 40 s: **mean 3.99 %**. See "Known cost" below. |
| 13 | A peek stays open while the pointer is inside and restarts its hold on leave | PASS (unit) | Same tests as #6. |
| 14 | The hook self-heal notice appears as a banner card | PASS | Deleted Reef's 14 Claude hook entries; they were restored and the banner rendered with the measured warm surface, icon circle and dismiss button (`t5-banner2.png`). |

## Stage 1 criteria re-checked after the panel rewrite

| Stage 1 # | Criterion | Result | Evidence |
|---|---|---|---|
| 2 | Bash permission Allow / Deny round trip | PASS | Allow returned the exact decision JSON during the clickability test. |
| 4 | Completion card, sound, collapse | PASS | Completion card renders through the new Markdown renderer; collapse timing unchanged. |
| 8 | AskUserQuestion answered from the notch | PASS (unit) | `QuestionSelection` and `QuestionAnswer` tests unchanged and green. |
| 9 | ExitPlanMode approve / deny | PASS | Plan card rendered and Approve wired; `t9-md3.png`. |
| 10 | Parallel requests, oldest first | PASS | `pendingRequests` ordering unchanged; `testTwoWaitRequestsAreIndependent`. |
| 13 | Hook self-heal | PASS | Same run as Stage 2 #14. |
| 14 | Six Settings tabs | PASS | Integrations gained the status-line row; all tabs build and render. |

## Known cost

One animating session costs about **4 % CPU**. The sprite itself is a small canvas at 6.6 frames per second; the cost comes from the transparent, always-on-top panel recompositing its whole surface on each tick. The idle case is free (0.12 %), so this is the price of the animation the stage exists to add, not a leak. Worth revisiting if battery life suffers: candidates are drawing the sprite into a cached layer, or dropping idle sessions to a slower heartbeat than working ones.

## Environment notes

- Vibe Island owns Claude Code's `statusLine` on this Mac, so Reef's usage shim is not installed; Settings says so and names the owner. The header figures above came from a hand-written cache file. Removing Vibe Island frees the slot and the Install button appears.
- Accessibility is still not granted to the ad hoc signed `Reef.app`, so the Ghostty jump and the keyboard shortcuts remain unexercised, as in Stage 1.
