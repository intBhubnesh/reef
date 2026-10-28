#!/bin/bash
# Usage: scripts/dev/send.sh <fixture.json|path> [claude|codex]
# Pipes a hook-event fixture through the debug reef-bridge and prints the agent-facing stdout.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURE="$1"; SOURCE="${2:-claude}"
[ -f "$FIXTURE" ] || FIXTURE="$ROOT/scripts/dev/fixtures/$1"
sed "s#__HOME__#$HOME#g; s#__ROOT__#$ROOT#g" "$FIXTURE" | "$ROOT/.build/debug/reef-bridge" --source "$SOURCE"
