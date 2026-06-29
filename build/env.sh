#!/usr/bin/env bash
# Shared environment for winevideo builds. Source this; do not execute.
set -euo pipefail

export WV_ROOT="$HOME/.local/winevideo"
export WV_SRC="$WV_ROOT/src/wine"
export WV_BUILD="$WV_ROOT/build/wine"

# Reused cxGE assets (read-only)
export LLVM_MINGW="$HOME/.local/cxge/toolchains/llvm-mingw"
export FFMPEG_INSTALL="$HOME/.local/cxge/install/ffmpeg"   # FFmpeg 7.1 (matches CX26 libavcodec.61)

# x86_64 Homebrew
export BREW_PREFIX="/usr/local"

# CrossOver runtime
export CX_APP="/Applications/CrossOver.app"
export CX_LIB="$CX_APP/Contents/SharedSupport/CrossOver/lib"
export CX_LIB64="$CX_APP/Contents/SharedSupport/CrossOver/lib64"
export CX_WINE_PE="$CX_LIB/wine/x86_64-windows"
export CX_WINE_UNIX="$CX_LIB/wine/x86_64-unix"
export CX_BIN="$CX_APP/Contents/SharedSupport/CrossOver/bin"

export PATH="$LLVM_MINGW/bin:$BREW_PREFIX/bin:$BREW_PREFIX/sbin:$PATH"

# keg-only Homebrew + FFmpeg include/lib/pkgconfig discovery.
# Exported here so BOTH configure and make see them (gnutls/freetype headers etc.
# live under /usr/local/include or /usr/local/opt/<pkg>/include, not in clang's
# default search path). Without this, dlls/bcrypt/gnutls.c fails at make time.
_WV_BREW_PKGS="freetype gnutls sdl2 libpcap gettext libvpx opus flac libvorbis libogg gstreamer glib"
_wv_pkg="$FFMPEG_INSTALL/lib/pkgconfig:$BREW_PREFIX/lib/pkgconfig"
_wv_inc="$BREW_PREFIX/include:$FFMPEG_INSTALL/include"
_wv_lib="$BREW_PREFIX/lib:$FFMPEG_INSTALL/lib"
for _p in $_WV_BREW_PKGS; do
  _d="$BREW_PREFIX/opt/$_p"
  [ -d "$_d/lib/pkgconfig" ] && _wv_pkg="$_d/lib/pkgconfig:$_wv_pkg"
  [ -d "$_d/include" ] && _wv_inc="$_d/include:$_wv_inc"
  [ -d "$_d/lib" ] && _wv_lib="$_d/lib:$_wv_lib"
done
export PKG_CONFIG_PATH="$_wv_pkg:${PKG_CONFIG_PATH:-}"
export CPATH="$_wv_inc:${CPATH:-}"
export LIBRARY_PATH="$_wv_lib:${LIBRARY_PATH:-}"
