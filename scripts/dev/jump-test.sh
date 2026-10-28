#!/bin/bash
# Manual Task 12 verification: kitty jump + approvals-follow-focus. Run from the repo root with reef-app NOT running.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOCK="$(ls /tmp/kitty-* 2>/dev/null | head -1)"
export KITTY_LISTEN_ON="unix:$SOCK" KITTY_WINDOW_ID=1 KITTY_PID="${SOCK##*-}" __CFBundleIdentifier=net.kovidgoyal.kitty TERM_PROGRAM=kitty
S=/private/tmp/claude-501/-Users-mint-Code-rea/3ab9f58f-fd45-4eb4-81e7-f52d23242362/scratchpad
LOG=~/Library/Logs/Reef/reef.log
send() { sed "s#__ROOT__#$ROOT#g" "$ROOT/scripts/dev/fixtures/$1" | "$ROOT/.build/debug/reef-bridge" --source claude; }
focused() { kitten @ --to "unix:$SOCK" ls | python3 -c "import json,sys; print([w['id'] for o in json.load(sys.stdin) for t in o['tabs'] for w in t['windows'] if w['is_focused']])"; }

pkill -x reef-app; sleep 0.5
("$ROOT/.build/debug/reef-app" >/dev/null 2>&1 &); sleep 2
send session-start.json >/dev/null; send prompt.json >/dev/null

echo "== 1. open a second kitty window (takes focus), then jump back to window 1 via the card"
kitten @ --to "unix:$SOCK" launch --type=os-window >/dev/null; sleep 1
echo "focused before jump: $(focused)"
"$S/mouse" hover 800 20; for i in 1 2 3 4; do "$S/mouse" hover $((800+i*5)) 18; sleep 0.4; done; sleep 1
screencapture -x -R 455,0,800,300 "$S/reef-jump-panel.png"
"$S/mouse" click 855 110; sleep 1.5
echo "focused after jump:  $(focused)"
grep '"c":"jump"' "$LOG" | tail -3 | cut -c1-160
kitten @ --to "unix:$SOCK" close-window --match id:2 2>/dev/null

echo "== 2. request while kitty is frontmost -> released to terminal immediately"
osascript -e 'tell application "kitty" to activate'; sleep 0.7
START=$(python3 -c 'import time;print(time.time())')
OUT=$(send bash-permission.json)
END=$(python3 -c 'import time;print(time.time())')
echo "stdout=$OUT elapsed=$(python3 -c "print(round($END-$START,3))")s"
grep 'released to terminal' "$LOG" | tail -1 | cut -c1-120
screencapture -x -R 455,0,800,300 "$S/reef-readonly.png"

echo "== 3. request while Finder is frontmost -> held; then focusing kitty releases it"
osascript -e 'tell application "Finder" to activate'; sleep 0.7
(send bash-permission.json > "$S/out-held.txt"; python3 -c 'import time;print("released_at",time.time())' >> "$S/out-held.txt") &
sleep 1.5
echo "held after 1.5s (file should be empty): [$(cat "$S/out-held.txt")]"
T0=$(python3 -c 'import time;print(time.time())')
osascript -e 'tell application "kitty" to activate'
sleep 0.5
echo "after activating kitty at $T0:"; cat "$S/out-held.txt"
pkill -x reef-app
