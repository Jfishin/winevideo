#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PATCHER="$ROOT/patcher/patch.sh"
RESTORE="$ROOT/patcher/restore.sh"
GUI="$ROOT/gui/WineVideoPatcher.swift"
BUILD_GUI="$ROOT/gui/build-app.sh"
HANDLE_PATCH="$ROOT/build/patches/0008-d3d9-dxmt-video-bridge-handle.patch"
UPLOAD_PATCH="$ROOT/build/patches/0009-d3d9-dxmt-video-bridge-upload.patch"
D3D9="$ROOT/patcher/payload/wine-pe/d3d9.dll"
EXPECTED_D3D9_SHA="b5e3dd0ed178b79ffbc391e1ca7a5de28daf625d2c19453f9f5a21e6002abddb"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
need_file() { [ -f "$1" ] || fail "missing $1"; }
need_text() { rg -q -- "$2" "$1" || fail "$1 does not contain: $2"; }

for f in "$PATCHER" "$RESTORE" "$GUI" "$BUILD_GUI" "$HANDLE_PATCH" "$UPLOAD_PATCH" "$D3D9"; do
  need_file "$f"
done

for p in "$ROOT"/build/patches/*.patch; do
  head -n 1 "$p" | grep -q '^diff --git ' || fail "$p is not a neutral diff patch"
  if rg -qi '^(From:|Date:|Subject:|Co-Authored-By:)' "$p"; then
    fail "$p contains mail-style metadata"
  fi
done

need_text "$ROOT/build/patches/SOURCES.md" '0008.*D3D9.*bridge'
need_text "$ROOT/build/patches/SOURCES.md" '0009.*D3D9.*bridge'
need_text "$ROOT/build/README.md" '0008-d3d9-dxmt-video-bridge-handle'
need_text "$ROOT/build/README.md" '0009-d3d9-dxmt-video-bridge-upload'
need_text "$ROOT/build/env.sh" 'ffile-prefix-map'
need_text "$ROOT/build/env.sh" 'fdebug-prefix-map'

actual_sha="$(shasum -a 256 "$D3D9" | awk '{print $1}')"
[ "$actual_sha" = "$EXPECTED_D3D9_SHA" ] || fail "unexpected d3d9.dll hash: $actual_sha"

need_text "$PATCHER" 'backup .*d3d9\.dll'
need_text "$PATCHER" 'wine-pe/d3d9\.dll'
need_text "$PATCHER" 'WINE_D3D9_DXMT_VIDEO_BRIDGE'
need_text "$PATCHER" 'CX_GRAPHICS_BACKEND'
need_text "$PATCHER" '26\.2'
need_text "$PATCHER" '26\.3'
# The bridge uses Wine's normal builtin D3D9 selection and must not write any
# executable-specific or bottle-wide D3D9 override.
if rg -n 'AppDefaults|DllOverrides.*d3d9|/v d3d9' "$PATCHER" "$RESTORE"; then
  fail "patcher or restore script contains a D3D9 override"
fi

need_text "$RESTORE" 'd3d9\.dll'
need_text "$RESTORE" 'WINE_D3D9_DXMT_VIDEO_BRIDGE'
need_text "$RESTORE" 'CX_GRAPHICS_BACKEND'

need_text "$GUI" 'CrossOver 26\.2 & 26\.3'
need_text "$GUI" 'D3D9-to-DXMT'
if rg -n 'Ninja Gaiden|Nioh|Persona 5|[Pp]rivate draft|experimental' "$GUI"; then
  fail "GUI contains game-specific or draft wording"
fi

need_text "$BUILD_GUI" '0008-d3d9-dxmt-video-bridge-handle\.patch'
need_text "$BUILD_GUI" '0009-d3d9-dxmt-video-bridge-upload\.patch'
need_text "$BUILD_GUI" 'SOURCES\.md'

bash -n "$PATCHER"
bash -n "$RESTORE"
bash -n "$BUILD_GUI"

printf 'PASS: D3D9-to-DXMT patcher release contract\n'
