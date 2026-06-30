#!/usr/bin/env bash
# =============================================================================
#  winevideo VP9 patcher for CrossOver 26.2  (drag-and-drop friendly)
# =============================================================================
#  Adds real VP9 (+VP8/WebM/Matroska) video support to a CrossOver 26.2 app and
#  fixes the d3dmetal "NV12 video texture" crash, so Media-Foundation video
#  games (e.g. Ninja Gaiden 4) play their cutscenes.
#
#  USAGE:
#    1. Duplicate your CrossOver.app (keep the original pristine).
#    2. Run:  ./patch.sh /path/to/CrossOver-copy.app  [bottle ...]
#       - no bottle args  -> patches the APP + EVERY existing bottle
#       - bottle args      -> patches the APP + only those bottles
#
#  STAGING (no admin / no Full Disk Access needed): if the path you pass does
#  NOT end in ".app" (e.g. ".../CrossOver-winevideo"), it is treated as a plain
#  staging folder. macOS "App Management" only protects real .app bundles, so a
#  folder can be patched + signed as the normal user with no elevation; this
#  script then renames it to "<name>.app" at the very end. The GUI uses this.
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

# Optional mode flag (must be first). Kept for compatibility / CLI:
#   --app-only    = only patch the app files (+ finalize/rename)
#   --bottle-only = only register the per-bottle registry (app must already be .app)
# The GUI uses neither: it passes a staging folder and lets MODE=all do everything.
MODE=all
case "${1:-}" in --app-only) MODE=app; shift;; --bottle-only) MODE=bottle; shift;; esac

APP="${1:-}"
[ -z "$APP" ] && { echo "usage: $0 [--app-only|--bottle-only] /path/to/CrossOver(.app) [bottle ...]"; exit 2; }
[ -d "$APP/Contents/SharedSupport/CrossOver" ] || { echo "ERROR: not a CrossOver app: $APP"; exit 2; }
shift || true
SEL_BOTTLES=("$@")

# Staging detection: a path without a .app extension is a staging folder we will
# rename to <name>.app after patching+signing. FINAL is the eventual .app path;
# the backup is always keyed off FINAL so restore.sh finds it.
case "$APP" in *.app) STAGE=0; FINAL="$APP";; *) STAGE=1; FINAL="${APP}.app";; esac
BK="${FINAL}.winevideo-backup"; mkdir -p "$BK"   # kept OUTSIDE the bundle (never affects the seal)
FINAL_LIB64="$FINAL/Contents/SharedSupport/CrossOver/lib64"   # rpath target = the EVENTUAL .app path
# Optional RE Engine / extra codecs come from the USER's own official GStreamer 1.24.x
# framework (we never ship FFmpeg). If it isn't installed, that step is simply skipped.
GST_FW="/Library/Frameworks/GStreamer.framework/Versions/1.0"
GST_DL="https://gstreamer.freedesktop.org/data/pkg/osx/1.24.13/gstreamer-1.0-1.24.13-universal.pkg"

compute_paths(){
  SS="$APP/Contents/SharedSupport/CrossOver"
  LIB64="$SS/lib64"; PLUGDIR="$LIB64/gstreamer-1.0"
  WINE_PE="$SS/lib/wine/x86_64-windows"; WINE_UNIX="$SS/lib/wine/x86_64-unix"; BIN="$SS/bin"
}
compute_paths

echo "=== winevideo VP9 patcher -> $FINAL ==="
[ "$STAGE" = 1 ] && echo "    (staging as a folder, no elevation needed; will rename to .app at the end)"

# Remove quarantine so macOS doesn't SIGKILL ("Killed: 9") the wine binaries in a
# copied/downloaded bundle. NEVER codesign --deep the app: that strips CrossOver's
# entitlements (JIT / executable memory) and Wine silently stops working. We only
# ad-hoc sign the individual dylibs we add (fix_so) + re-seal the top bundle.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null

backup(){ local rel="$1" src="$2"; [ -f "$BK/$rel" ] || { [ -f "$src" ] && cp "$src" "$BK/$rel"; }; }

# Repoint a .so/.dylib's @rpath gst/glib refs to the app's lib64, compat-rewrite
# framework (2414) versions to CX26.2 (2405/glib 7801), ad-hoc sign.
# IMPORTANT: the rpath must point to lib64 in the FINAL location, not where the file
# physically sits during patching. When staging, files are patched in a folder that is
# then renamed to .app — an absolute rpath to the folder would dangle after the rename.
# So we add (1) a @loader_path-relative rpath (relocation-proof: survives the rename AND
# the user later moving/renaming the app) and (2) the absolute final-.app lib64 as a
# belt-and-suspenders fallback (this matches the proven pre-staging behavior).
fix_so(){ local so="$1"
  # CX wine is x86_64-only. Thin any universal (fat) dylib to x86_64 so the compat-version
  # rewrite (which only handles thin 64-bit Mach-O) actually applies — and it halves size.
  if lipo -archs "$so" 2>/dev/null | grep -q arm64; then
    lipo "$so" -thin x86_64 -output "$so.x86_64only" 2>/dev/null && mv -f "$so.x86_64only" "$so"
  fi
  for rp in $(otool -l "$so" 2>/dev/null | awk '/LC_RPATH/{getline;getline;print $2}'); do
    case "$rp" in *gst-framework*|*usr/local*|*homebrew*|*/opt/*) install_name_tool -delete_rpath "$rp" "$so" 2>/dev/null;; esac
  done
  local sodir rel
  sodir="$(cd "$(dirname "$so")" && pwd)"
  rel="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$SS/lib64" "$sodir" 2>/dev/null)"
  [ -n "$rel" ] && install_name_tool -add_rpath "@loader_path/$rel" "$so" 2>/dev/null
  install_name_tool -add_rpath "$FINAL_LIB64" "$so" 2>/dev/null
  [ -f "$COMPAT" ] && python3 "$COMPAT" "$so" >/dev/null 2>&1
  codesign -f -s - "$so" 2>/dev/null
}

# Copy a dylib from the user's GStreamer framework into the app's lib64 and recursively
# pull its @rpath FFmpeg deps, adapting each (rpath/compat/sign). Used ONLY for the
# optional RE Engine codecs — we do not ship these; they come from the user's GStreamer.
pull_gst_lib(){ local name="$1"
  local dst="$LIB64/$name"; [ -f "$dst" ] && return 0
  local src="$GST_FW/lib/$name"; [ -f "$src" ] || return 1
  cp "$src" "$dst"; fix_so "$dst"
  local dep
  for dep in $(otool -L "$dst" 2>/dev/null | awk '/@rpath\/lib(av|sw)/{print $1}'); do
    pull_gst_lib "$(basename "$dep")"
  done
}

# ---------------------------------------------------------------------------
#  APP FILES + FINALIZE (verify, re-seal, rename staging folder -> .app)
# ---------------------------------------------------------------------------
if [ "$MODE" != bottle ]; then
  echo "--- app: winegstreamer (VP9/AV1 caps) + mfplat (NV12->BGRA fallback) ---"
  backup "winegstreamer.dll" "$WINE_PE/winegstreamer.dll"
  backup "winegstreamer.so"  "$WINE_UNIX/winegstreamer.so"
  backup "mfplat.dll"        "$WINE_PE/mfplat.dll"
  cp "$PAY/wine-pe/winegstreamer.dll" "$WINE_PE/winegstreamer.dll"
  cp "$PAY/wine-pe/mfplat.dll"        "$WINE_PE/mfplat.dll"
  cp "$PAY/wine-unix/winegstreamer.so" "$WINE_UNIX/winegstreamer.so"; fix_so "$WINE_UNIX/winegstreamer.so"

  # Guard: only patch a real CrossOver 26.2 layout. CrossOver Preview / other builds
  # have no lib64/gstreamer-1.0 and ship a different Wine/GStreamer ABI, so our
  # binaries won't load — fail clearly instead of producing a broken app.
  if [ ! -d "$PLUGDIR" ]; then
    VER="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null)"
    echo ""
    echo "❌ Unsupported CrossOver build${VER:+ ($VER)} — no $(basename "$LIB64")/gstreamer-1.0 plugin dir."
    echo "   winevideo supports the stable CrossOver 26.2 release only (not CrossOver Preview)."
    exit 3
  fi

  echo "--- app: VP9 + matroska GStreamer plugins + runtime deps ---"
  mkdir -p "$PLUGDIR"   # safety no-op once the guard above has passed
  for p in vpx matroska; do
    cp "$PAY/lib64/gstreamer-1.0/libgst${p}.dylib" "$PLUGDIR/libgst${p}.dylib"; fix_so "$PLUGDIR/libgst${p}.dylib"
  done
  for d in libvpx.9.dylib liborc-0.4.0.dylib libz.1.dylib libbz2.1.dylib; do
    [ -f "$LIB64/$d" ] || cp "$PAY/lib64/$d" "$LIB64/$d"   # don't clobber the app's own
  done

  echo "--- app: enable applemedia (VideoToolbox h264/hevc), if present disabled ---"
  [ -f "$PLUGDIR/libgstapplemedia.dylib.disabled" ] && cp "$PLUGDIR/libgstapplemedia.dylib.disabled" "$PLUGDIR/libgstapplemedia.dylib"

  # ---- optional: RE Engine / extra codecs, sourced from the USER's GStreamer ----
  # We never ship FFmpeg. If the user installed the official GStreamer 1.24.x framework,
  # pull libgstlibav (+ its FFmpeg deps) from THEIR copy → avdec_vc1/wmv3/wmav2 (WMV/VC-1/
  # WMA: DMC5, RE2/3/8, MHW logo movies) + h264/aac/ac3. Skipped cleanly if not installed.
  echo "--- app: optional RE Engine codecs (libgstlibav from your GStreamer, if installed) ---"
  GST_LA="$GST_FW/lib/gstreamer-1.0/libgstlibav.dylib"
  if [ ! -f "$GST_LA" ]; then
    echo "    (skipped) For RE Engine / WMV / extra video (DMC5, RE2/3/8, MHW), install the"
    echo "    official GStreamer 1.24.x framework (default install), then re-run the patcher:"
    echo "      $GST_DL"
  else
    gv=$(otool -L "$GST_LA" 2>/dev/null | grep 'libglib-2.0.0.dylib' | sed -nE 's/.*compatibility version ([0-9]+).*/\1/p' | head -1)
    if [ "${gv:-0}" -ge 8001 ]; then
      echo "    (skipped) Your GStreamer is too new (glib $gv ≥ 2.80) for CrossOver's glib 2.78."
      echo "    Install GStreamer 1.24.x specifically: $GST_DL"
    else
      cp "$GST_LA" "$PLUGDIR/libgstlibav.dylib"
      for dep in $(otool -L "$GST_LA" 2>/dev/null | awk '/@rpath\/lib(av|sw)/{print $1}'); do
        pull_gst_lib "$(basename "$dep")"
      done
      fix_so "$PLUGDIR/libgstlibav.dylib"
      nlib=$(ls "$LIB64"/lib{av,sw}*.dylib 2>/dev/null | wc -l | tr -d ' ')
      echo "    RE Engine codecs added from your GStreamer ✓ (libgstlibav + $nlib FFmpeg libs)"
    fi
  fi

  # ---- verify the app files actually landed ----
  MISSING=""
  for f in "$WINE_PE/winegstreamer.dll" "$WINE_PE/mfplat.dll" "$WINE_UNIX/winegstreamer.so" \
           "$PLUGDIR/libgstvpx.dylib" "$PLUGDIR/libgstmatroska.dylib" "$LIB64/libvpx.9.dylib"; do
    [ -f "$f" ] || MISSING="$MISSING\n    - $f"
  done
  if [ -n "$MISSING" ]; then
    echo ""
    echo "❌ PATCH INCOMPLETE — these files did not get written:$MISSING"
    echo "   Check free disk space, and that the payload next to this script is intact."
    echo "   (If you patched a path ending in .app directly, macOS App Management may be"
    echo "    blocking writes — pass a folder path without the .app extension instead, or"
    echo "    grant Full Disk Access and re-run.)"
    exit 1
  fi

  # Modifying the bundle breaks its original code-signature seal -> Finder refuses to
  # launch it ("damaged"). Re-seal ad-hoc WITHOUT --deep: rebuilds a valid
  # CodeResources over the modified contents and ad-hoc-signs only the main
  # executable, while the nested wine binaries keep their Developer-ID signatures +
  # JIT entitlements. (--deep would re-sign everything ad-hoc and STRIP those
  # entitlements -> wine silently stops working.) Do this WHILE it is still a plain
  # folder (when staging) so App Management can't block the codesign either.
  echo "--- re-seal the bundle ad-hoc so it launches (keeps wine entitlements) ---"
  for s in CodeResources _CodeSignature; do   # clean up any seal renamed aside by old runs
    [ -e "$APP/Contents/${s}_disabled" ] && [ ! -e "$APP/Contents/$s" ] && mv -f "$APP/Contents/${s}_disabled" "$APP/Contents/$s" 2>/dev/null
    rm -rf "$APP/Contents/${s}_disabled" 2>/dev/null
  done
  SEAL_ERR="$(mktemp -t wv_seal 2>/dev/null || echo "$BK/.seal.err")"
  if codesign --force --sign - "$APP" 2>"$SEAL_ERR"; then echo "    re-sealed ✓"
  else echo "    ⚠️ re-seal failed: $(grep -iE 'error|unsealed' "$SEAL_ERR" 2>/dev/null | head -1)"; fi
  rm -f "$SEAL_ERR" 2>/dev/null

  # Staging: now that it is patched + signed as a folder, rename to .app.
  if [ "$STAGE" = 1 ]; then
    rm -rf "$FINAL" 2>/dev/null
    mv "$APP" "$FINAL"
    APP="$FINAL"; STAGE=0; compute_paths
    echo "    renamed to $(basename "$FINAL") ✓"
  fi
  xattr -dr com.apple.quarantine "$APP" 2>/dev/null
fi

if [ "$MODE" = app ]; then echo "=== app patched: $APP (originals in $BK) ==="; exit 0; fi

# ---------------------------------------------------------------------------
#  PER-BOTTLE REGISTRY  (runs wine from the final .app; writes ~/Library only)
# ---------------------------------------------------------------------------
patch_bottle(){ local b="$1"; local dir="$BOTTLES/$b"
  [ -e "$dir/system.reg" ] || { echo "    skip $b (no system.reg)"; return; }
  echo "    bottle: $b"
  export CX_BOTTLE="$b" WINEDLLOVERRIDES="mscoree,mshtml=d"
  "$BIN/wineserver" -k 2>/dev/null
  # A brand-new bottle's first wine call runs the (slow) auto-init; a real command
  # forces it to complete. Then write the keys. CRUCIAL: Wine only flushes the
  # registry to system.reg ~5s AFTER a change — so we must NOT hard-kill or check
  # immediately. We write, then POLL system.reg (leaving wineserver alive) until the
  # key appears (the flush), retrying the writes if it doesn't.
  "$BIN/wine" cmd /c ver >/dev/null 2>&1
  cp "$PAY/reg/vp9-mft.reg" "$dir/drive_c/vp9-mft.reg" 2>/dev/null
  local n=0
  while [ $n -lt 3 ]; do
    "$BIN/wine" regedit /S 'C:\vp9-mft.reg' >/dev/null 2>&1
    for ext in .webm .mkv .msd; do
      "$BIN/wine" reg add "HKLM\\Software\\Microsoft\\Windows Media Foundation\\ByteStreamHandlers\\$ext" /v "$GBSH" /d "GStreamer Byte Stream Handler" /f >/dev/null 2>&1
    done
    local w=0
    while [ $w -lt 12 ]; do sleep 1; grep -qi "e3aaf548" "$dir/system.reg" 2>/dev/null && break; w=$((w+1)); done
    grep -qi "e3aaf548" "$dir/system.reg" 2>/dev/null && break
    n=$((n+1))
  done
  rm -f "$dir/drive_c/vp9-mft.reg" 2>/dev/null
  "$BIN/wineserver" -k 2>/dev/null   # safe now: keys already flushed to disk
  if grep -qi "e3aaf548" "$dir/system.reg" 2>/dev/null; then echo "      VP9 decoder MFT registered ✓"
  else echo "      ⚠️ VP9 registration did NOT land in $b — run the patcher on this bottle again"; fi
}

echo "--- bottles: register VP9 decoder MFT + webm/mkv/msd handlers ---"
if [ "${#SEL_BOTTLES[@]}" -gt 0 ]; then
  for b in "${SEL_BOTTLES[@]}"; do patch_bottle "$b"; done
else
  for dir in "$BOTTLES"/*/; do patch_bottle "$(basename "$dir")"; done
fi
# refresh gstreamer plugin registry so the new plugins are scanned
find "$HOME/Library/Application Support/CrossOver" -iname "*gstreamer*registry*x86_64*" -delete 2>/dev/null

if [ "$MODE" = bottle ]; then echo "=== bottle registration done ($APP) ==="; exit 0; fi
echo "=== DONE. Patched $APP (originals backed up in $BK). Restore with restore.sh ==="
