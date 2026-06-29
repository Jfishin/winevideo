#!/usr/bin/env bash
# =============================================================================
#  winevideo VP9 patcher for CrossOver 26.2  (drag-and-drop friendly)
# =============================================================================
#  Adds real VP9 (+VP8/WebM/Matroska) video support to a CrossOver 26.2 app and
#  fixes the d3dmetal/DXMT "NV12 video texture" crash, so Media-Foundation video
#  games (e.g. Ninja Gaiden 4) play their cutscenes.
#
#  USAGE:
#    1. Duplicate your CrossOver.app (keep the original pristine).
#    2. Run:  ./patch.sh /path/to/CrossOver-copy.app  [bottle ...]
#       - no bottle args  -> patches the APP + EVERY existing bottle
#       - bottle args      -> patches the APP + only those bottles
#
#  The APP-level DLLs apply to all bottles. The per-bottle registry (VP9 decoder
#  + .webm/.mkv/.msd handlers) is required and is stamped into each bottle.
#  Re-run with a bottle name to patch a newly-created bottle later.
#
#  Reversible:  ./restore.sh /path/to/CrossOver-copy.app [bottle ...]
# =============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PAY="$HERE/payload"
COMPAT="$PAY/patch_macho_compat.py"
GBSH='{317df618-5e5a-468a-9f15-d827a9a08162}'   # CLSID_GStreamerByteStreamHandler
BOTTLES="$HOME/Library/Application Support/CrossOver/Bottles"

APP="${1:-}"
[ -z "$APP" ] && { echo "usage: $0 /path/to/CrossOver.app [bottle ...]"; exit 2; }
[ -d "$APP/Contents/SharedSupport/CrossOver" ] || { echo "ERROR: not a CrossOver app: $APP"; exit 2; }
shift || true
SEL_BOTTLES=("$@")

SS="$APP/Contents/SharedSupport/CrossOver"
LIB64="$SS/lib64"
PLUGDIR="$LIB64/gstreamer-1.0"
WINE_PE="$SS/lib/wine/x86_64-windows"
WINE_UNIX="$SS/lib/wine/x86_64-unix"
BIN="$SS/bin"
BK="$APP/.winevideo-backup"; mkdir -p "$BK"

echo "=== winevideo VP9 patcher -> $APP ==="

# Remove quarantine so macOS doesn't SIGKILL ("Killed: 9") the wine binaries in a
# copied/downloaded bundle. NEVER codesign --deep the app: that strips CrossOver's
# entitlements (JIT / executable memory) and Wine silently stops working. We only
# ad-hoc sign the individual dylibs we add (see fix_so), preserving wine's signature.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null

backup(){ local rel="$1" src="$2"; [ -f "$BK/$rel" ] || { [ -f "$src" ] && cp "$src" "$BK/$rel"; }; }

# Repoint a .so/.dylib's @rpath gst/glib refs to the target app's lib64, compat-
# rewrite framework (2414) versions to CX26.2 (2405/glib 7801), ad-hoc sign.
fix_so(){ local so="$1"
  for rp in $(otool -l "$so" 2>/dev/null | awk '/LC_RPATH/{getline;getline;print $2}'); do
    case "$rp" in *gst-framework*|*usr/local*|*homebrew*|*/opt/*) install_name_tool -delete_rpath "$rp" "$so" 2>/dev/null;; esac
  done
  install_name_tool -add_rpath "$LIB64" "$so" 2>/dev/null
  [ -f "$COMPAT" ] && python3 "$COMPAT" "$so" >/dev/null 2>&1
  codesign -f -s - "$so" 2>/dev/null
}

echo "--- app: winegstreamer (VP9/AV1 caps) + mfplat (NV12->BGRA fallback) ---"
backup "winegstreamer.dll" "$WINE_PE/winegstreamer.dll"
backup "winegstreamer.so"  "$WINE_UNIX/winegstreamer.so"
backup "mfplat.dll"        "$WINE_PE/mfplat.dll"
cp "$PAY/wine-pe/winegstreamer.dll" "$WINE_PE/winegstreamer.dll"
cp "$PAY/wine-pe/mfplat.dll"        "$WINE_PE/mfplat.dll"
cp "$PAY/wine-unix/winegstreamer.so" "$WINE_UNIX/winegstreamer.so"; fix_so "$WINE_UNIX/winegstreamer.so"

echo "--- app: VP9 + matroska GStreamer plugins + runtime deps ---"
for p in vpx matroska; do
  cp "$PAY/lib64/gstreamer-1.0/libgst${p}.dylib" "$PLUGDIR/libgst${p}.dylib"; fix_so "$PLUGDIR/libgst${p}.dylib"
done
for d in libvpx.9.dylib liborc-0.4.0.dylib libz.1.dylib libbz2.1.dylib; do
  [ -f "$LIB64/$d" ] || cp "$PAY/lib64/$d" "$LIB64/$d"   # don't clobber the app's own
done

echo "--- app: enable applemedia (VideoToolbox h264/hevc), if present disabled ---"
[ -f "$PLUGDIR/libgstapplemedia.dylib.disabled" ] && cp "$PLUGDIR/libgstapplemedia.dylib.disabled" "$PLUGDIR/libgstapplemedia.dylib"

# ---- per-bottle registry ----
patch_bottle(){ local b="$1"; local dir="$BOTTLES/$b"
  [ -d "$dir/system.reg" -o -f "$dir/system.reg" ] || { echo "    skip $b (no system.reg)"; return; }
  echo "    bottle: $b"
  export CX_BOTTLE="$b" WINEDLLOVERRIDES="mscoree,mshtml=d"
  "$BIN/wineserver" -k 2>/dev/null
  cp "$PAY/reg/vp9-mft.reg" "$dir/drive_c/vp9-mft.reg" 2>/dev/null
  "$BIN/wine" regedit /S 'C:\vp9-mft.reg' >/dev/null 2>&1
  for ext in .webm .mkv .msd; do
    "$BIN/wine" reg add "HKLM\\Software\\Microsoft\\Windows Media Foundation\\ByteStreamHandlers\\$ext" /v "$GBSH" /d "GStreamer Byte Stream Handler" /f >/dev/null 2>&1
  done
  "$BIN/wineserver" -k 2>/dev/null
  rm -f "$dir/drive_c/vp9-mft.reg" 2>/dev/null
}

echo "--- bottles: register VP9 decoder MFT + webm/mkv/msd handlers ---"
if [ "${#SEL_BOTTLES[@]}" -gt 0 ]; then
  for b in "${SEL_BOTTLES[@]}"; do patch_bottle "$b"; done
else
  for dir in "$BOTTLES"/*/; do patch_bottle "$(basename "$dir")"; done
fi
# refresh gstreamer plugin registry so the new plugins are scanned
find "$HOME/Library/Application Support/CrossOver" -iname "*gstreamer*registry*x86_64*" -delete 2>/dev/null

# ---- verify the app files actually landed (catches silent TCC/permission denials) ----
MISSING=""
for f in "$WINE_PE/winegstreamer.dll" "$WINE_PE/mfplat.dll" "$WINE_UNIX/winegstreamer.so" \
         "$PLUGDIR/libgstvpx.dylib" "$PLUGDIR/libgstmatroska.dylib" "$LIB64/libvpx.9.dylib"; do
  [ -f "$f" ] || MISSING="$MISSING\n    - $f"
done
if [ -n "$MISSING" ]; then
  echo ""
  echo "❌ PATCH INCOMPLETE — these files did not get written:$MISSING"
  echo "   This is almost always macOS blocking writes into the app bundle."
  echo "   Fix: keep the patched app in your HOME ~/Applications folder (not /Applications),"
  echo "   or grant this app Full Disk Access in System Settings ▸ Privacy & Security, then re-run."
  exit 1
fi

echo "=== DONE. Patched $APP (originals backed up in $BK). Restore with restore.sh ==="
