#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"; source ./env.sh

ok=1
chk() { if eval "$2" >/dev/null 2>&1; then echo "  OK   $1"; else echo "  MISS $1"; ok=0; fi; }

echo "=== winevideo toolchain check ==="
chk "x86_64 Homebrew"        "[ -x $BREW_PREFIX/bin/brew ]"
chk "llvm-mingw clang"       "[ -x $LLVM_MINGW/bin/x86_64-w64-mingw32-clang ]"
chk "llvm-mingw gcc"         "[ -x $LLVM_MINGW/bin/x86_64-w64-mingw32-gcc ]"
chk "FFmpeg 7.1 install dir" "[ -d $FFMPEG_INSTALL/include/libavcodec ]"
chk "bison (brew)"           "[ -x $BREW_PREFIX/opt/bison/bin/bison ]"
chk "flex"                   "command -v flex"
chk "gstreamer pc (brew)"    "[ -e $BREW_PREFIX/opt/gstreamer/lib/pkgconfig/gstreamer-1.0.pc ]"
chk "source tarball"         "[ -f /Users/jfishin/Downloads/crossover-sources-26.2.0.tar.gz ]"
chk "CrossOver 26 app"       "[ -d $CX_APP ]"
chk "mf_probe.c"             "[ -f $(git rev-parse --show-toplevel)/mf_probe.c ]"

echo "ffmpeg libavcodec version in $FFMPEG_INSTALL:"
grep -h LIBAVCODEC_VERSION_M "$FFMPEG_INSTALL/include/libavcodec/version_major.h" 2>/dev/null | sed 's/^/  /' || echo "  (version_major.h not found)"
[ $ok -eq 1 ] && echo "ALL PRESENT" || echo "MISSING ITEMS — see Task 2 / cxGE bootstrap.sh"
