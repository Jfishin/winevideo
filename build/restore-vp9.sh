#!/usr/bin/env bash
# Revert the VP9 patch from a CrossOver app + bottle back to stock.
#   CX_APP=/path/to/CrossOver.app CX_BOTTLE=<bottle> bash restore-vp9.sh
# Restores winegstreamer.{dll,so} from realapp-backup, deletes the plugin/dep
# files we added, and removes the VP9 MFT + byte-stream-handler registry keys.
set -uo pipefail
cd "$(dirname "$0")"; source ./env.sh; set +e
BK="$HOME/.local/winevideo/realapp-backup"
PLUGDIR="$CX_LIB64/gstreamer-1.0"

echo "=== restore winegstreamer.{dll,so} + mfplat.dll from backup ==="
if [ -f "$BK/winegstreamer.dll" ] && [ -f "$BK/winegstreamer.so" ]; then
  cp "$BK/winegstreamer.dll" "$CX_WINE_PE/winegstreamer.dll" && echo "  restored winegstreamer.dll"
  cp "$BK/winegstreamer.so"  "$CX_WINE_UNIX/winegstreamer.so" && echo "  restored winegstreamer.so"
else
  echo "  WARNING: no backup found at $BK — skipping dll/so restore"
fi
[ -f "$BK/mfplat.dll" ] && cp "$BK/mfplat.dll" "$CX_WINE_PE/mfplat.dll" && echo "  restored mfplat.dll"

echo "=== remove added plugins + bundled deps ==="
for f in "$PLUGDIR/libgstvpx.dylib" "$PLUGDIR/libgstmatroska.dylib"; do
  [ -f "$f" ] && rm -f "$f" && echo "  removed $(basename "$f")"
done
# only remove a bundled dep if it was NOT in the pre-patch lib64 snapshot
if [ -f "$BK/lib64.before.txt" ]; then
  for dep in libvpx.9.dylib liborc-0.4.0.dylib libz.1.dylib libbz2.1.dylib; do
    if ! grep -qx "$dep" "$BK/lib64.before.txt" && [ -f "$CX_LIB64/$dep" ]; then
      rm -f "$CX_LIB64/$dep" && echo "  removed bundled dep $dep"
    fi
  done
fi

echo "=== remove VP9 MFT + byte-stream-handler registry keys (bottle ${CX_BOTTLE:-Test}) ==="
export CX_BOTTLE="${CX_BOTTLE:-Test}" WINEDLLOVERRIDES="mscoree,mshtml=d"
BOTTLE_C="$HOME/Library/Application Support/CrossOver/Bottles/${CX_BOTTLE}/drive_c"
"$CX_BIN/wineserver" -k 2>/dev/null
cp ./vp9-mft-uninstall.reg "$BOTTLE_C/vp9-mft-uninstall.reg"
"$CX_BIN/wine" regedit /S 'C:\vp9-mft-uninstall.reg' >/dev/null 2>&1
"$CX_BIN/wineserver" -k 2>/dev/null
rm -f "$BOTTLE_C/vp9-mft-uninstall.reg"

find "$HOME/Library/Application Support/CrossOver" -iname "*gstreamer*registry*x86_64*" -delete 2>/dev/null
echo "Restored $CX_APP (bottle ${CX_BOTTLE}) to stock."
