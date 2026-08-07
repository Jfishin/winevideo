#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
APP="$HERE/winevideo Patcher.app"
DIST="$ROOT/dist"
ZIP="${1:-$DIST/winevideo-Patcher-macOS.zip}"

case "$ZIP" in
  /*) ;;
  *) ZIP="$PWD/$ZIP" ;;
esac

bash "$HERE/build-app.sh"
xattr -cr "$APP" 2>/dev/null || true
mkdir -p "$(dirname "$ZIP")"
rm -f "$ZIP"

(
  cd "$HERE"
  COPYFILE_DISABLE=1 /usr/bin/zip -r -X -q "$ZIP" \
    "winevideo Patcher.app" \
    -x '*/.DS_Store' '*/._*'
)

if unzip -Z1 "$ZIP" | grep -Eq '(^|/)\._|(^|/)\.DS_Store$'; then
  echo "ERROR: release ZIP contains Finder metadata" >&2
  exit 1
fi

echo "Built release: $ZIP"
shasum -a 256 "$ZIP"
