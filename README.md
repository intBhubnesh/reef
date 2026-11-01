# Reef

A macOS notch app that watches your AI coding agents (Claude Code, Codex) and makes two moments impossible to miss: an agent needs your input, and an agent finished. Approve, deny and answer from the notch; click a session to jump to its terminal.

```sh
swift build            # debug build of reef-app and reef-bridge
swift test             # ReefCore unit tests
scripts/bundle.sh      # dist/Reef.app (ad hoc signed)
scripts/release.sh     # universal app + versioned DMG + SHA-256 checksum
```

Design: `docs/superpowers/specs/2026-10-28-reef-design.md`. Plan: `docs/superpowers/plans/2026-10-28-reef-stage1.md`.

Codex in VS Code never runs hooks, so Reef reads its transcripts instead and shows those sessions read-only; see `docs/protocol.md` section 7.

Reef honours the system "reduce motion" setting: agent avatar animation freezes and transitions become short fades.

## Bark notifications

Settings → Notifications can send input-needed, finished, and failed alerts to the
[Bark iOS app](https://github.com/Finb/Bark). Enter the server (`https://api.day.app` by default)
and paste either the device key or complete test URL from Bark, then use **Send test**. Self-hosted bark-server URLs are
supported. Reef uses Bark's JSON `POST /push` API; the device key is stored in macOS Keychain and
notification bodies contain only project/status metadata, never prompts or command contents.

The circular agent avatar is a native SwiftUI adaptation of the MIT-licensed
[Bloub](https://github.com/jeremy-prt/bloub) animation model. See
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## Install a release build

Reef 1.0 requires macOS 14 or newer and supports both Apple silicon and Intel Macs.

1. Open `Reef-1.0.0-universal.dmg`.
2. Drag **Reef** into **Applications**.
3. On the first launch, open **Applications**, Control-click Reef, choose **Open**, then confirm.
4. Complete Reef's setup and grant Automation access when macOS asks. Accessibility access is
   optional and is only needed for precise window focusing in supported terminals.

The current public build is ad-hoc signed because this project does not yet have an Apple
Developer ID certificate. The Control-click step is therefore expected. A Developer ID-signed
and notarized build can remove that step later without changing the app.
