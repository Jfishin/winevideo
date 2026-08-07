#!/usr/bin/env bash
# Compile the SwiftUI patcher and bundle it with the patch script + payload.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"                 # winevideo/
APP="$HERE/winevideo Patcher.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"
MODULE_CACHE="${TMPDIR:-/tmp}/winevideo-swift-module-cache"

rm -rf "$APP"
mkdir -p "$MACOS" "$RES" "$MODULE_CACHE"

echo "=== compiling SwiftUI app ==="
swiftc "$HERE/WineVideoPatcher.swift" -O -parse-as-library \
  -o "$MACOS/winevideo-patcher" \
  -framework SwiftUI -framework AppKit -framework UniformTypeIdentifiers \
  -target arm64-apple-macos14.0 \
  -module-cache-path "$MODULE_CACHE"

echo "=== Info.plist ==="
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>winevideo Patcher</string>
  <key>CFBundleDisplayName</key><string>winevideo Patcher</string>
  <key>CFBundleIdentifier</key><string>com.winevideo.patcher</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>winevideo-patcher</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict></plist>
PLIST

echo "=== bundling patch script + payload into Resources ==="
cp "$ROOT/patcher/patch.sh" "$ROOT/patcher/restore.sh" "$RES/"
chmod +x "$RES/patch.sh" "$RES/restore.sh"
cp -R "$ROOT/patcher/payload" "$RES/payload"
mkdir -p "$RES/source-patches"
cp "$ROOT/build/patches/0008-d3d9-dxmt-video-bridge-handle.patch" "$RES/source-patches/"
cp "$ROOT/build/patches/0009-d3d9-dxmt-video-bridge-upload.patch" "$RES/source-patches/"
cp "$ROOT/build/patches/SOURCES.md" "$RES/source-patches/"

echo "=== ad-hoc sign ==="
codesign -f -s - --deep "$APP" 2>/dev/null || true

echo "Built: $APP"
du -sh "$APP" | sed 's/^/  /'
