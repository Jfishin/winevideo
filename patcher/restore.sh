#!/usr/bin/env bash
# Revert a winevideo-patched CrossOver app (+ bottles) to stock.
#   ./restore.sh /path/to/CrossOver.app [bottle ...]
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PAY="$HERE/payload"
BOTTLES="${WINEVIDEO_BOTTLES_DIR:-$HOME/Library/Application Support/CrossOver/Bottles}"

APP="${1:-}"
[ -z "$APP" ] && { echo "usage: $0 /path/to/CrossOver.app [bottle ...]"; exit 2; }
shift || true
SEL_BOTTLES=("$@")

SS="$APP/Contents/SharedSupport/CrossOver"
LIB64="$SS/lib64"; PLUGDIR="$LIB64/gstreamer-1.0"
WINE_PE="$SS/lib/wine/x86_64-windows"; WINE_UNIX="$SS/lib/wine/x86_64-unix"; BIN="$SS/bin"
BK="${APP}.winevideo-backup"; [ -d "$BK" ] || BK="$APP/.winevideo-backup"   # new (sibling) or legacy (inside)

echo "=== restore $APP to stock ==="
# legacy cleanup: older versions renamed the seal aside
for s in CodeResources _CodeSignature; do
  [ -e "$APP/Contents/${s}_disabled" ] && [ ! -e "$APP/Contents/$s" ] && mv -f "$APP/Contents/${s}_disabled" "$APP/Contents/$s" 2>/dev/null
  rm -rf "$APP/Contents/${s}_disabled" 2>/dev/null
done
[ -f "$BK/winegstreamer.dll" ] && cp "$BK/winegstreamer.dll" "$WINE_PE/winegstreamer.dll" && echo "  winegstreamer.dll"
[ -f "$BK/winegstreamer.so" ]  && cp "$BK/winegstreamer.so"  "$WINE_UNIX/winegstreamer.so" && echo "  winegstreamer.so"
[ -f "$BK/mfplat.dll" ]        && cp "$BK/mfplat.dll"        "$WINE_PE/mfplat.dll" && echo "  mfplat.dll"
[ -f "$BK/d3d9.dll" ]          && cp "$BK/d3d9.dll"          "$WINE_PE/d3d9.dll" && echo "  d3d9.dll"
# remove the plugins + deps we added (only if they weren't part of the stock app)
rm -f "$PLUGDIR/libgstvpx.dylib" "$PLUGDIR/libgstmatroska.dylib" && echo "  removed vpx/matroska plugins"
# re-seal the (now stock-content) bundle ad-hoc so it still launches cleanly
codesign --force --sign - "$APP" 2>/dev/null && echo "  re-sealed (ad-hoc)"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null

restore_bottle_env(){ local conf="$1" original="$2" key="$3"
  WV_KEY="$key" perl -0pi -e '
    my $key = quotemeta("\"$ENV{WV_KEY}\"");
    s/^$key\s*=.*\n//mg;
  ' "$conf"
  local line
  line="$(grep -F "\"$key\"" "$original" 2>/dev/null | head -1 || true)"
  if [ -n "$line" ]; then
    WV_LINE="$line" perl -0pi -e 's/(\[EnvironmentVariables\]\n)/$1$ENV{WV_LINE}\n/' "$conf"
  fi
}

patch_bottle_restore(){ local b="$1"; local dir="$BOTTLES/$b"
  [ -e "$dir/system.reg" ] || return
  echo "    bottle: $b"
  local bottle_backup="$BK/bottles/$b" conf="$dir/cxbottle.conf"
  export CX_BOTTLE="$b" WINEDLLOVERRIDES="mscoree,mshtml=d"
  "$BIN/wineserver" -k 2>/dev/null
  "$BIN/wine" cmd /c ver >/dev/null 2>&1
  cp "$PAY/reg/vp9-mft-uninstall.reg" "$dir/drive_c/vp9-mft-uninstall.reg" 2>/dev/null
  "$BIN/wine" regedit /S 'C:\vp9-mft-uninstall.reg' >/dev/null 2>&1
  "$BIN/wineserver" -k 2>/dev/null
  rm -f "$dir/drive_c/vp9-mft-uninstall.reg" 2>/dev/null
  if [ -f "$bottle_backup/cxbottle.conf.before-video-bridge" ]; then
    restore_bottle_env "$conf" "$bottle_backup/cxbottle.conf.before-video-bridge" CX_GRAPHICS_BACKEND
    restore_bottle_env "$conf" "$bottle_backup/cxbottle.conf.before-video-bridge" WINE_D3D9_DXMT_VIDEO_BRIDGE
  fi
  echo "      D3D9-to-DXMT bottle settings restored ✓"
}
echo "--- bottles: remove VP9 MFT + handlers ---"
if [ "${#SEL_BOTTLES[@]}" -gt 0 ]; then
  for b in "${SEL_BOTTLES[@]}"; do patch_bottle_restore "$b"; done
else
  echo "    (none selected; app restored only)"
fi
for b in "${SEL_BOTTLES[@]}"; do
  find "$BOTTLES/$b" -iname "*gstreamer*registry*x86_64*" -delete 2>/dev/null
done
echo "=== restored ==="
