#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/tests/probes/d3d9-bridge"
OUT="${WINEVIDEO_TEST_BUILD_DIR:-$ROOT/tests/.build/probes}"
CC="${WINEVIDEO_MINGW_CC:-}"

if [ -z "$CC" ]; then
  CC="$(command -v x86_64-w64-mingw32-gcc 2>/dev/null || true)"
fi
if [ -z "$CC" ] || [ ! -x "$CC" ]; then
  echo "ERROR: x86_64 MinGW compiler not found." >&2
  echo "Set WINEVIDEO_MINGW_CC to the compiler path." >&2
  exit 1
fi

mkdir -p "$OUT"

"$CC" -std=c11 -Wall -Wextra -Werror -municode \
  "$SRC/probe_common.c" "$SRC/dxmt_shared_probe.c" \
  -o "$OUT/dxmt_shared_probe.exe" \
  -ld3d11 -ldxgi -ldxguid -lole32

"$CC" -std=c11 -Wall -Wextra -Werror -municode \
  "$SRC/probe_common.c" "$SRC/d3d9_bridge_probe.c" \
  -o "$OUT/d3d9_bridge_probe.exe" \
  -ld3d9 -ld3d11 -ldxgi -ldxguid -lole32 -luser32

printf 'built=%s\n' "$OUT/dxmt_shared_probe.exe"
printf 'built=%s\n' "$OUT/d3d9_bridge_probe.exe"
