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
