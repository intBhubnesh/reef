# Reef

A macOS notch app that watches your AI coding agents (Claude Code, Codex) and makes two moments impossible to miss: an agent needs your input, and an agent finished. Approve, deny and answer from the notch; click a session to jump to its terminal.

```sh
swift build            # debug build of reef-app and reef-bridge
swift test             # ReefCore unit tests
scripts/bundle.sh      # dist/Reef.app (ad hoc signed)
```

Design: `docs/superpowers/specs/2026-10-28-reef-design.md`. Plan: `docs/superpowers/plans/2026-10-28-reef-stage1.md`.

Codex in VS Code never runs hooks, so Reef reads its transcripts instead and shows those sessions read-only; see `docs/protocol.md` section 7.

Reef honours the system "reduce motion" setting: stepped sprite animation freezes and transitions become short fades.
