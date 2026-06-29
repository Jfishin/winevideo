#!/usr/bin/env bash
# Build libgstvpx (vp9dec/vp8dec) + libgstmatroska (matroskademux) as loadable
# GStreamer plugins from the 1.24.13 framework STATIC libs + our shims.
# CrossOver ships neither plugin, and brew's are glib-2.80+ (won't load in CX's glib 2.78).
# The framework static libs are glib-2.74 → clean. We drop each .a's own GST_PLUGIN_DEFINE
# object and supply our shim (exports gst_plugin_<name>_get_desc that GStreamer 1.24 dlsym's).
set -uo pipefail
cd "$(dirname "$0")"; source ./env.sh; set +e
FW="$HOME/.local/winevideo/gst-framework"; SDK="$(xcrun --show-sdk-path)"
DIST="$HOME/.local/winevideo/dist"; mkdir -p "$DIST"
[ -d "$FW/Headers" ] || { echo "ERROR: GStreamer 1.24 framework not extracted at $FW (see winegstreamer-vp9-recipe.md)"; exit 3; }

build_plugin(){ local name="$1"; local shim="$2"; shift 2
  local A="$FW/lib/gstreamer-1.0/libgst${name}.a"
  local obj="/tmp/${name}obj"; rm -rf "$obj"; mkdir -p "$obj"; ( cd "$obj"
    lipo "$A" -thin x86_64 -output thin.a 2>/dev/null || cp "$A" thin.a
    ar x thin.a; rm -f plugin.c.o "${name}.c.o" )   # drop the .a's own GST_PLUGIN_DEFINE
  arch -x86_64 clang -dynamiclib -arch x86_64 -isysroot "$SDK" -o "$DIST/libgst${name}.dylib" \
    -install_name "@rpath/libgst${name}.dylib" -I"$FW/Headers" \
    "$shim" "$obj"/*.o -L"$FW/lib" "$@" \
    -lgobject-2.0 -lglib-2.0 -lgmodule-2.0 -lorc-0.4 -liconv -lm -Wl,-rpath,"$FW/lib"
  if nm -gU "$DIST/libgst${name}.dylib" 2>/dev/null | grep -q "gst_plugin_${name}_get_desc"; then
    echo "  OK  built $DIST/libgst${name}.dylib"
  else echo "  FAIL $name (no exported descriptor)"; fi
}
echo "=== building VP9 + matroska plugins ==="
build_plugin vpx       build/gst-plugins/vpx_shim.c      -lgstreamer-1.0 -lgstbase-1.0 -lgstvideo-1.0 -lgsttag-1.0 -lgstpbutils-1.0 -lgstaudio-1.0 -lvpx
build_plugin matroska  build/gst-plugins/matroska_shim.c -lgstreamer-1.0 -lgstbase-1.0 -lgstvideo-1.0 -lgstaudio-1.0 -lgsttag-1.0 -lgstpbutils-1.0 -lgstriff-1.0 -lz -lbz2
