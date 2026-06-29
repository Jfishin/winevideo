#!/usr/bin/env arch -x86_64 bash
set -euo pipefail
cd "$(dirname "$0")"; source ./env.sh
cd "$WV_BUILD"

SDK="$(xcrun --show-sdk-path)"
# Use the SYSTEM clang (via xcrun), NOT llvm-mingw's clang which is first in PATH and
# returns a bare filename for the macOS compiler-rt. Absolute path required for linking.
CLANG_RT="$(xcrun clang -arch x86_64 -print-file-name=libclang_rt.osx.a 2>/dev/null)"
[ -f "$CLANG_RT" ] || CLANG_RT="$(/usr/bin/find /Library/Developer/CommandLineTools/usr/lib/clang -name libclang_rt.osx.a 2>/dev/null | head -1)"
[ -f "$CLANG_RT" ] || { echo "ERROR: libclang_rt.osx.a not found" >&2; exit 3; }
MAKE_LDFLAGS="-arch x86_64 -Wl,-headerpad_max_install_names -Wl,-rpath,@loader_path/../lib -Wl,-rpath,$BREW_PREFIX/lib -Wl,-rpath,$FFMPEG_INSTALL/lib -isysroot $SDK -Wl,-syslibroot,$SDK $CLANG_RT"

TARGET="${1:-}"   # empty = full build; or pass e.g. dlls/winedmo
make -j"$(sysctl -n hw.ncpu)" LDFLAGS="$MAKE_LDFLAGS" $TARGET
