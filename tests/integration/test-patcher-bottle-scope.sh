#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d /private/tmp/winevideo-bottle-scope.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
CX_VERSION="${WINEVIDEO_TEST_CX_VERSION:-26.2}"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

APP="$TMP/CrossOver-test.app"
CX="$APP/Contents/SharedSupport/CrossOver"
BIN="$CX/bin"
BOTTLES="$TMP/Bottles"
LOG="$TMP/wine-calls.log"

mkdir -p "$BIN" "$CX/lib64/gstreamer-1.0" "$CX/lib/wine/x86_64-windows" \
  "$CX/lib/wine/x86_64-unix" "$BOTTLES/TestBottle/drive_c" "$BOTTLES/OtherBottle/drive_c"

printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
  "<plist version=\"1.0\"><dict><key>CFBundleShortVersionString</key><string>$CX_VERSION</string></dict></plist>" \
  > "$APP/Contents/Info.plist"

printf '%s\n' '[EnvironmentVariables]' '"CX_GRAPHICS_BACKEND" = "metal"' > "$BOTTLES/TestBottle/cxbottle.conf"
printf '%s\n' '[EnvironmentVariables]' '"UNCHANGED" = "1"' > "$BOTTLES/OtherBottle/cxbottle.conf"
printf '%s\n' 'e3aaf548' > "$BOTTLES/TestBottle/system.reg"
printf '%s\n' 'e3aaf548' > "$BOTTLES/OtherBottle/system.reg"

cat > "$BIN/wine" <<'MOCK'
#!/usr/bin/env bash
printf 'wine %s\n' "$*" >> "$WINEVIDEO_TEST_LOG"
if [ "${1:-}" = reg ] && [ "${2:-}" = query ]; then exit 1; fi
exit 0
MOCK
cat > "$BIN/wineserver" <<'MOCK'
#!/usr/bin/env bash
printf 'wineserver %s\n' "$*" >> "$WINEVIDEO_TEST_LOG"
exit 0
MOCK
chmod +x "$BIN/wine" "$BIN/wineserver"

WINEVIDEO_TEST_LOG="$LOG" WINEVIDEO_BOTTLES_DIR="$BOTTLES" \
  bash "$ROOT/patcher/patch.sh" --bottle-only "$APP" TestBottle >/dev/null

grep -q '^"CX_GRAPHICS_BACKEND" = "dxmt"$' "$BOTTLES/TestBottle/cxbottle.conf"
grep -q '^"WINE_D3D9_DXMT_VIDEO_BRIDGE" = "1"$' "$BOTTLES/TestBottle/cxbottle.conf"
if grep -Fq 'AppDefaults' "$LOG" || grep -Fq '/v d3d9' "$LOG"; then
  fail "patcher wrote a D3D9 DLL override"
fi
grep -q '^"UNCHANGED" = "1"$' "$BOTTLES/OtherBottle/cxbottle.conf"

WINEVIDEO_TEST_LOG="$LOG" WINEVIDEO_BOTTLES_DIR="$BOTTLES" \
  bash "$ROOT/patcher/restore.sh" "$APP" TestBottle >/dev/null

grep -q '^"CX_GRAPHICS_BACKEND" = "metal"$' "$BOTTLES/TestBottle/cxbottle.conf"
if grep -q 'WINE_D3D9_DXMT_VIDEO_BRIDGE' "$BOTTLES/TestBottle/cxbottle.conf"; then
  fail "restore left the bridge environment enabled"
fi
if grep -Fq 'AppDefaults' "$LOG" || grep -Fq '/v d3d9' "$LOG"; then
  fail "patcher or restore touched a D3D9 DLL override"
fi
grep -q '^"UNCHANGED" = "1"$' "$BOTTLES/OtherBottle/cxbottle.conf"

printf 'PASS: CrossOver %s selected-bottle D3D9 bridge environment and restore\n' "$CX_VERSION"
