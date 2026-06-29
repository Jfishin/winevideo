#!/usr/bin/env bash
# Drop the framework-built winegstreamer (VP9/AV1) into $CX_APP, fix linkage to
# CrossOver's bundled GStreamer, and register webm/mkv/msd byte-stream handlers.
# Build first: see build/winegstreamer-vp9-recipe.md
set -uo pipefail
cd "$(dirname "$0")"; source ./env.sh; set +e
COMPAT="$HOME/Documents/projects/Wdebug/NG4/patch_macho_compat.py"
GBSH="{317df618-5e5a-468a-9f15-d827a9a08162}"   # CLSID_GStreamerByteStreamHandler
SO="$CX_WINE_UNIX/winegstreamer.so"

cp "$WV_BUILD/dlls/winegstreamer/x86_64-windows/winegstreamer.dll" "$CX_WINE_PE/winegstreamer.dll"
cp "$WV_BUILD/dlls/winegstreamer/winegstreamer.so" "$SO"
# resolve @rpath to CrossOver's single GStreamer (remove framework/brew rpaths, add CX lib64)
for rp in $(otool -l "$SO" | awk '/LC_RPATH/{getline;getline;print $2}'); do
  case "$rp" in *gst-framework*|*usr/local*) install_name_tool -delete_rpath "$rp" "$SO" 2>/dev/null;; esac
done
install_name_tool -add_rpath "$CX_LIB64" "$SO" 2>/dev/null
python3 "$COMPAT" "$SO" >/dev/null 2>&1      # compat 2414->2405, glib->7801
codesign --force --sign - "$SO" 2>/dev/null

# register container handlers in the bottle
export CX_BOTTLE="${CX_BOTTLE:-Test}" WINEDLLOVERRIDES="mscoree,mshtml=d"
"$CX_BIN/wineserver" -k 2>/dev/null
for ext in .webm .mkv .msd; do
  "$CX_BIN/wine" reg add "HKLM\\Software\\Microsoft\\Windows Media Foundation\\ByteStreamHandlers\\$ext" \
    /v "$GBSH" /d "GStreamer Byte Stream Handler" /f >/dev/null 2>&1
done
"$CX_BIN/wineserver" -k 2>/dev/null
echo "winegstreamer VP9 build installed into $CX_APP (bottle $CX_BOTTLE); webm/mkv/msd handlers registered"
