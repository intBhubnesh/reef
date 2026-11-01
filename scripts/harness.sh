#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h}
ARTIFACTS=${REEF_ARTIFACTS:-$ROOT/.artifacts/harness}
CACHE=${TMPDIR:-/tmp}/reef-harness-module-cache
mkdir -p "$ARTIFACTS" "$CACHE"

export CLANG_MODULE_CACHE_PATH="$CACHE"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE"

swift test --package-path "$ROOT"
swift build --package-path "$ROOT"

BIN=$(swift build --package-path "$ROOT" --show-bin-path)/reef-app
: > "$ARTIFACTS/timeline.jsonl"
for scenario in closed opened approval question completion failure; do
  "$BIN" "--reef-scenario=$scenario" "--reef-snapshot-path=$ARTIFACTS/$scenario.json" >"$ARTIFACTS/$scenario.log" 2>&1 &
  pid=$!
  wait "$pid"
  printf '{"scenario":"%s","verifiedAt":%s}\n' "$scenario" "$(date +%s)" >> "$ARTIFACTS/timeline.jsonl"
done

cat > "$ARTIFACTS/report.json" <<EOF
{"build":"passed","tests":"passed","visualCapture":${REEF_CAPTURE:-0},"scenarios":["closed","opened","approval","question","completion","failure"]}
EOF

if [[ "${REEF_CAPTURE:-0}" == "1" ]]; then
  for scenario in closed opened approval question completion failure; do
    pkill -x reef-app >/dev/null 2>&1 || true
    "$BIN" "--reef-scenario=$scenario" >"$ARTIFACTS/$scenario.log" 2>&1 &
    pid=$!
    sleep 1
    screencapture -x "$ARTIFACTS/$scenario.png"
    printf '{"scenario":"%s","capturedAt":%s}\n' "$scenario" "$(date +%s)" >> "$ARTIFACTS/timeline.jsonl"
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" 2>/dev/null || true
  done
fi

echo "$ARTIFACTS/report.json"
