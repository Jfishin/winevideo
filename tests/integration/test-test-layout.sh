#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_PROBES="$ROOT/tests/scripts/build-d3d9-bridge-probes.sh"
TEST_README="$ROOT/tests/README.md"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

for file in \
  "$ROOT/tests/probes/d3d9-bridge/d3d9_bridge_probe.c" \
  "$ROOT/tests/probes/d3d9-bridge/dxmt_shared_probe.c" \
  "$ROOT/tests/probes/media-foundation/mf_probe.c" \
  "$BUILD_PROBES" \
  "$TEST_README"; do
  [ -f "$file" ] || fail "missing test asset: $file"
done

bash -n "$BUILD_PROBES"

if find "$ROOT" -maxdepth 1 -name '*probe*.c' -print -quit | grep -q .; then
  fail "probe source remains at the repository root"
fi

if find "$ROOT" -maxdepth 1 -type f \
    \( -name '*probe*.exe' -o -name '*probe*.log' -o -name '*probe*.dxvk-cache' \) \
    -print -quit | grep -q .; then
  fail "generated probe artifact remains at the repository root"
fi

printf 'PASS: reusable test layout\n'
