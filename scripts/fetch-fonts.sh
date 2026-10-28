#!/bin/bash
# Downloads Departure Mono (OFL) from its upstream release into Resources/Fonts (git-ignored).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/Resources/Fonts"
TMP="$(mktemp -d)"
curl -fsSL -o "$TMP/dm.zip" "https://github.com/rektdeckard/departure-mono/releases/download/v1.500/DepartureMono-1.500.zip"
unzip -q -o "$TMP/dm.zip" -d "$TMP"
find "$TMP" -name "DepartureMono-Regular.otf" -exec cp {} "$ROOT/Resources/Fonts/" \;
find "$TMP" -iname "LICENSE*" -exec cp {} "$ROOT/Resources/Fonts/DepartureMono-LICENSE.txt" \; 2>/dev/null || true
ls -la "$ROOT/Resources/Fonts"
