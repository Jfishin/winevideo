#!/usr/bin/env bash
# Full VP9 (and matroska/webm) playback patch for a CrossOver app ($CX_APP).
# Installs: winegstreamer (VP9/AV1 caps), libgstvpx (vp9dec), libgstmatroska
# (matroskademux), their runtime deps, enables applemedia (HW h264/hevc), and
# registers webm/mkv/msd byte-stream handlers. Validate with mf_probe.
# Build the pieces first: build/make-wine.sh (winegstreamer) + build/build-gst-plugins.sh.
set -uo pipefail
cd "$(dirname "$0")"; source ./env.sh; set +e
FW="$HOME/.local/winevideo/gst-framework"; DIST="$HOME/.local/winevideo/dist"
COMPAT="$HOME/Documents/projects/Wdebug/NG4/patch_macho_compat.py"
PLUGDIR="$CX_LIB64/gstreamer-1.0"
GBSH="{317df618-5e5a-468a-9f15-d827a9a08162}"   # CLSID_GStreamerByteStreamHandler

# Repoint a .so/.dylib's @rpath GStreamer/glib refs to CrossOver's bundled libs,
# bundle any missing deps from the framework, compat-rewrite (2414->2405 etc.), sign.
fix_so(){ local so="$1"
  for rp in $(otool -l "$so" 2>/dev/null | awk '/LC_RPATH/{getline;getline;print $2}'); do
    case "$rp" in *gst-framework*|*usr/local*) install_name_tool -delete_rpath "$rp" "$so" 2>/dev/null;; esac
  done
  install_name_tool -add_rpath "$CX_LIB64" "$so" 2>/dev/null
  otool -L "$so" 2>/dev/null | grep -aoE "@rpath/lib[^ ]+dylib" | while read d; do
    local b; b=$(basename "$d")
    if [ ! -f "$CX_LIB64/$b" ] && [ "$b" != "$(basename "$so")" ]; then
      local src; src=$(find "$FW/lib" -maxdepth 1 -name "$b" 2>/dev/null | head -1)
      [ -z "$src" ] && src=$(find "$FW/lib" -maxdepth 1 -name "${b%%.*}*.dylib" 2>/dev/null | head -1)
      [ -n "$src" ] && cp "$src" "$CX_LIB64/$b" && install_name_tool -id "@rpath/$b" "$CX_LIB64/$b" 2>/dev/null && codesign -f -s - "$CX_LIB64/$b" 2>/dev/null && echo "  bundled dep $b"
    fi
  done
  python3 "$COMPAT" "$so" >/dev/null 2>&1
  codesign -f -s - "$so" 2>/dev/null
}

echo "=== winegstreamer (VP9/AV1 caps) ==="
cp "$WV_BUILD/dlls/winegstreamer/x86_64-windows/winegstreamer.dll" "$CX_WINE_PE/winegstreamer.dll"
cp "$WV_BUILD/dlls/winegstreamer/winegstreamer.so" "$CX_WINE_UNIX/winegstreamer.so"; fix_so "$CX_WINE_UNIX/winegstreamer.so"

echo "=== mfplat (BGRA fallback so d3dmetal doesn't abort on NV12 video textures) ==="
cp "$WV_BUILD/dlls/mfplat/x86_64-windows/mfplat.dll" "$CX_WINE_PE/mfplat.dll"

echo "=== VP9 + matroska plugins ==="
for p in vpx matroska; do cp "$DIST/libgst${p}.dylib" "$PLUGDIR/libgst${p}.dylib"; fix_so "$PLUGDIR/libgst${p}.dylib"; done

echo "=== enable applemedia (VideoToolbox HW for h264/hevc) ==="
[ -f "$PLUGDIR/libgstapplemedia.dylib.disabled" ] && cp "$PLUGDIR/libgstapplemedia.dylib.disabled" "$PLUGDIR/libgstapplemedia.dylib"

echo "=== register webm/mkv/msd byte-stream handlers + rescan ==="
export CX_BOTTLE="${CX_BOTTLE:-Test}" WINEDLLOVERRIDES="mscoree,mshtml=d"
"$CX_BIN/wineserver" -k 2>/dev/null
for ext in .webm .mkv .msd; do
  "$CX_BIN/wine" reg add "HKLM\\Software\\Microsoft\\Windows Media Foundation\\ByteStreamHandlers\\$ext" /v "$GBSH" /d "GStreamer Byte Stream Handler" /f >/dev/null 2>&1
done
"$CX_BIN/wineserver" -k 2>/dev/null

echo "=== register VP9 decoder MFT (so MFTEnumEx advertises VP9 — game capability gate) ==="
# Games (e.g. Ninja Gaiden 4) call MFTEnumEx(MFT_CATEGORY_VIDEO_DECODER, VP90) and
# show "Failed to Play VP9" if it returns 0. This registers a REAL winegstreamer-backed
# VP9 decoder MFT (CLSID recognised by mfplat.c -> vp9_decoder_create). regedit /S is
# used because wine's `reg import`/`reg delete` silently no-op on these keys.
BOTTLE_C="$HOME/Library/Application Support/CrossOver/Bottles/${CX_BOTTLE}/drive_c"
cp ./vp9-mft.reg "$BOTTLE_C/vp9-mft.reg"
"$CX_BIN/wine" regedit /S 'C:\vp9-mft.reg' >/dev/null 2>&1
"$CX_BIN/wineserver" -k 2>/dev/null
rm -f "$BOTTLE_C/vp9-mft.reg"

find "$HOME/Library/Application Support/CrossOver" -iname "*gstreamer*registry*x86_64*" -delete 2>/dev/null
echo "VP9 patch installed into $CX_APP (bottle ${CX_BOTTLE:-Test})"
echo "  verify: CX_BOTTLE=${CX_BOTTLE} $CX_BIN/wine /tmp/mft_probe.exe vp9   # expect '1 decoder ADVERTISED'"
