#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PACKAGER="$ROOT/gui/build-release.sh"
RELEASE_ZIP="$ROOT/dist/winevideo-Patcher-macOS.zip"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[ -f "$PACKAGER" ] || fail "missing release packager"
bash -n "$PACKAGER"

bash "$PACKAGER"

[ -f "$RELEASE_ZIP" ] || fail "default release ZIP was not written under dist/"
[ ! -e "$ROOT/winevideo-Patcher-macOS.zip" ] || fail "default release ZIP remains at the repository root"
unzip -tq "$RELEASE_ZIP" >/dev/null || fail "release ZIP is invalid"

if unzip -Z1 "$RELEASE_ZIP" | grep -Eq '(^|/)\._|(^|/)\.DS_Store$'; then
  fail "release ZIP contains Finder metadata"
fi

printf 'PASS: clean release packager contract\n'
