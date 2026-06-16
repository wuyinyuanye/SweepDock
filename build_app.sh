#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT_DIR/SweepDock.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BUILD_DIR="$ROOT_DIR/build"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$BUILD_DIR/SweepDock.iconset"

clang -fobjc-arc \
  -framework Cocoa \
  "$ROOT_DIR/native/main.m" \
  -o "$MACOS_DIR/SweepDock"

chmod +x "$MACOS_DIR/SweepDock"

python3 - <<'PY' "$BUILD_DIR/SweepDock.iconset"
from pathlib import Path
import struct, zlib, sys

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)

def write_png(path, size):
    pixels = bytearray()
    for y in range(size):
        row = bytearray([0])
        for x in range(size):
            nx = (x + 0.5) / size
            ny = (y + 0.5) / size
            r = int(35 + 20 * nx)
            g = int(126 + 60 * (1 - ny))
            b = int(220 + 20 * ny)
            a = 255
            cx, cy = 0.5, 0.5
            d = ((nx - cx) ** 2 + ((ny - cy) * 1.08) ** 2) ** 0.5
            if d > 0.43:
                r, g, b = 245, 247, 250
            if 0.30 < d < 0.39 and abs((nx - ny) * 0.7) < 0.08:
                r, g, b = 18, 28, 42
            if 0.12 < d < 0.27 and nx > 0.32 and ny < 0.68:
                r, g, b = 255, 255, 255
            row.extend([r, g, b, a])
        pixels.extend(row)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)

    raw = bytes(pixels)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    Path(path).write_bytes(png)

for name, size in [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]:
    write_png(out / name, size)
PY

sips -s format tiff "$BUILD_DIR/SweepDock.iconset/icon_512x512@2x.png" --out "$BUILD_DIR/SweepDock.tiff" >/dev/null
tiff2icns "$BUILD_DIR/SweepDock.tiff" "$RESOURCES_DIR/SweepDock.icns"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>SweepDock</string>
  <key>CFBundleIconFile</key>
  <string>SweepDock</string>
  <key>CFBundleIdentifier</key>
  <string>local.sweepdock</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>SweepDock</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.8.0</string>
  <key>CFBundleVersion</key>
  <string>8</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "Built $APP_DIR"
