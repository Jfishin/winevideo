#!/usr/bin/env bash
# Revert a winevideo-patched CrossOver app (+ bottles) to stock.
#   ./restore.sh /path/to/CrossOver.app [bottle ...]
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PAY="$HERE/payload"
BOTTLES="$HOME/Library/Application Support/CrossOver/Bottles"

APP="${1:-}"
[ -z "$APP" ] && { echo "usage: $0 /path/to/CrossOver.app [bottle ...]"; exit 2; }
shift || true
SEL_BOTTLES=("$@")

SS="$APP/Contents/SharedSupport/CrossOver"
LIB64="$SS/lib64"; PLUGDIR="$LIB64/gstreamer-1.0"
WINE_PE="$SS/lib/wine/x86_64-windows"; WINE_UNIX="$SS/lib/wine/x86_64-unix"; BIN="$SS/bin"
BK="$APP/.winevideo-backup"

echo "=== restore $APP to stock ==="
[ -f "$BK/winegstreamer.dll" ] && cp "$BK/winegstreamer.dll" "$WINE_PE/winegstreamer.dll" && echo "  winegstreamer.dll"
[ -f "$BK/winegstreamer.so" ]  && cp "$BK/winegstreamer.so"  "$WINE_UNIX/winegstreamer.so" && echo "  winegstreamer.so"
[ -f "$BK/mfplat.dll" ]        && cp "$BK/mfplat.dll"        "$WINE_PE/mfplat.dll" && echo "  mfplat.dll"
# remove the plugins + deps we added (only if they weren't part of the stock app)
rm -f "$PLUGDIR/libgstvpx.dylib" "$PLUGDIR/libgstmatroska.dylib" && echo "  removed vpx/matroska plugins"

patch_bottle_restore(){ local b="$1"; local dir="$BOTTLES/$b"
  [ -e "$dir/system.reg" ] || return
  echo "    bottle: $b"
  export CX_BOTTLE="$b" WINEDLLOVERRIDES="mscoree,mshtml=d"
  "$BIN/wineserver" -k 2>/dev/null
  cp "$PAY/reg/vp9-mft-uninstall.reg" "$dir/drive_c/vp9-mft-uninstall.reg" 2>/dev/null
  "$BIN/wine" regedit /S 'C:\vp9-mft-uninstall.reg' >/dev/null 2>&1
  "$BIN/wineserver" -k 2>/dev/null
  rm -f "$dir/drive_c/vp9-mft-uninstall.reg" 2>/dev/null
}
echo "--- bottles: remove VP9 MFT + handlers ---"
if [ "${#SEL_BOTTLES[@]}" -gt 0 ]; then
  for b in "${SEL_BOTTLES[@]}"; do patch_bottle_restore "$b"; done
else
  for dir in "$BOTTLES"/*/; do patch_bottle_restore "$(basename "$dir")"; done
fi
find "$HOME/Library/Application Support/CrossOver" -iname "*gstreamer*registry*x86_64*" -delete 2>/dev/null
echo "=== restored ==="
