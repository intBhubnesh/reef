#!/bin/bash
# Renders Resources/AppIcon.icns: a black island with a blue pixel sprite, drawn with AppKit (no asset copying).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
cat > "$TMP/draw.swift" <<'EOF'
import AppKit
let args = CommandLine.arguments
let size = Int(args[1])!, out = args[2]
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let s = CGFloat(size)
let bg = NSBezierPath(roundedRect: NSRect(x: s*0.05, y: s*0.05, width: s*0.9, height: s*0.9), xRadius: s*0.2, yRadius: s*0.2)
NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.15, alpha: 1).setFill(); bg.fill()
// the island, hanging from the top edge
let island = NSBezierPath()
let w = s*0.56, h = s*0.2, x0 = (s-w)/2, top = s*0.95 - s*0.06, r = s*0.07
island.move(to: NSPoint(x: x0, y: top))
island.line(to: NSPoint(x: x0, y: top-h+r))
island.appendArc(withCenter: NSPoint(x: x0+r, y: top-h+r), radius: r, startAngle: 180, endAngle: 270)
island.line(to: NSPoint(x: x0+w-r, y: top-h))
island.appendArc(withCenter: NSPoint(x: x0+w-r, y: top-h+r), radius: r, startAngle: 270, endAngle: 360)
island.line(to: NSPoint(x: x0+w, y: top)); island.close()
NSColor.black.setFill(); island.fill()
// 5x5 sprite
let pattern = [[1,0,1,0,1],[0,1,1,1,0],[1,1,0,1,1],[0,1,1,1,0],[1,0,1,0,1]]
let px = s*0.052, gap = s*0.012
let gx = s/2 - (px*5+gap*4)/2, gy = s*0.3
NSColor(calibratedRed: 0.43, green: 0.63, blue: 1.0, alpha: 1).setFill()
for (row, cols) in pattern.enumerated() { for (col, on) in cols.enumerated() where on == 1 {
    NSBezierPath(rect: NSRect(x: gx + CGFloat(col)*(px+gap), y: gy + CGFloat(4-row)*(px+gap), width: px, height: px)).fill()
}}
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
EOF
swiftc -O -o "$TMP/draw" "$TMP/draw.swift" 2>/dev/null
for sz in 16 32 64 128 256 512 1024; do
  "$TMP/draw" "$sz" "$ICONSET/icon_${sz}x${sz}.png"
done
cp "$ICONSET/icon_32x32.png" "$ICONSET/icon_16x16@2x.png"
cp "$ICONSET/icon_64x64.png" "$ICONSET/icon_32x32@2x.png"
cp "$ICONSET/icon_256x256.png" "$ICONSET/icon_128x128@2x.png"
cp "$ICONSET/icon_512x512.png" "$ICONSET/icon_256x256@2x.png"
cp "$ICONSET/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"
rm "$ICONSET/icon_64x64.png" "$ICONSET/icon_1024x1024.png"
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
echo "$ROOT/Resources/AppIcon.icns"
