#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"; source ./env.sh
B="$WV_BUILD"
BK="$WV_ROOT/cx-backup"; mkdir -p "$BK"
PE_SRC="$B/dlls/winedmo/x86_64-windows/winedmo.dll"
SO_SRC="$B/dlls/winedmo/winedmo.so"

backup() {
  [ -f "$BK/winedmo.dll" ] || cp "$CX_WINE_PE/winedmo.dll" "$BK/winedmo.dll"
  [ -f "$BK/winedmo.so" ]  || cp "$CX_WINE_UNIX/winedmo.so" "$BK/winedmo.so"
  echo "  originals backed up in $BK"
}

# Repoint our winedmo.so's FFmpeg references from the build-time install (cxGE 7.1)
# to CrossOver's OWN bundled FFmpeg dylibs, so the patch is self-contained.
repoint() {
  local so="$1"
  for lib in libavformat.61.dylib libavcodec.61.dylib libavutil.59.dylib; do
    install_name_tool -change "$FFMPEG_INSTALL/lib/$lib" "$CX_LIB64/$lib" "$so" 2>/dev/null || true
  done
}

install_ours() {
  [ -f "$PE_SRC" ] || { echo "  ERROR: $PE_SRC not built"; exit 3; }
  [ -f "$SO_SRC" ] || { echo "  ERROR: $SO_SRC not built"; exit 3; }
  cp "$PE_SRC" "$CX_WINE_PE/winedmo.dll"
  cp "$SO_SRC" "$CX_WINE_UNIX/winedmo.so"
  repoint "$CX_WINE_UNIX/winedmo.so"
  codesign --force --sign - "$CX_WINE_UNIX/winedmo.so" 2>/dev/null || true   # ad-hoc re-sign after install_name edits
  echo "  installed our winedmo.{dll,so}; FFmpeg now resolves to CrossOver's bundle:"
  otool -L "$CX_WINE_UNIX/winedmo.so" | grep -iE "av(codec|format|util)" | sed 's/^/    /'
}

restore() {
  cp "$BK/winedmo.dll" "$CX_WINE_PE/winedmo.dll"
  cp "$BK/winedmo.so"  "$CX_WINE_UNIX/winedmo.so"
  echo "  restored original winedmo"
}

case "${1:-install}" in
  backup) backup;;
  install) backup; install_ours;;
  restore) restore;;
  *) echo "usage: dropin.sh [backup|install|restore]"; exit 2;;
esac
