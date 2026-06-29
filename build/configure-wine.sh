#!/usr/bin/env arch -x86_64 bash
set -euo pipefail
cd "$(dirname "$0")"; source ./env.sh

mkdir -p "$WV_BUILD"; cd "$WV_BUILD"

# keg-only Homebrew include/lib/pkgconfig discovery
BREW_PKGS="freetype gnutls sdl2 libpcap gettext libvpx opus flac libvorbis libogg gstreamer glib"
PKG_DIRS="$FFMPEG_INSTALL/lib/pkgconfig:$BREW_PREFIX/lib/pkgconfig"
INC_DIRS="$BREW_PREFIX/include:$FFMPEG_INSTALL/include"
LIB_DIRS="$BREW_PREFIX/lib:$FFMPEG_INSTALL/lib"
for pkg in $BREW_PKGS; do
  d="$BREW_PREFIX/opt/$pkg"
  [ -d "$d/lib/pkgconfig" ] && PKG_DIRS="$d/lib/pkgconfig:$PKG_DIRS"
  [ -d "$d/include" ] && INC_DIRS="$d/include:$INC_DIRS"
  [ -d "$d/lib" ] && LIB_DIRS="$d/lib:$LIB_DIRS"
done
export PKG_CONFIG_PATH="$PKG_DIRS:${PKG_CONFIG_PATH:-}"
export CPATH="$INC_DIRS:${CPATH:-}"
export LIBRARY_PATH="$LIB_DIRS:${LIBRARY_PATH:-}"

SDK="$(xcrun --show-sdk-path)"
export CC=clang CXX=clang++ MACOSX_DEPLOYMENT_TARGET=14.0
export CFLAGS="-O2 -Wno-deprecated-declarations -Wno-format -arch x86_64 -isysroot $SDK"
export CROSSCFLAGS="-O2 -Wno-incompatible-pointer-types"
export LDFLAGS="-arch x86_64 -Wl,-headerpad_max_install_names -Wl,-rpath,@loader_path/../lib -Wl,-rpath,$BREW_PREFIX/lib -Wl,-rpath,$FFMPEG_INSTALL/lib -isysroot $SDK -Wl,-syslibroot,$SDK"
export ac_cv_lib_soname_vulkan=""
export BISON="$BREW_PREFIX/opt/bison/bin/bison"

"$WV_SRC/configure" \
  --prefix="$WV_ROOT/install/wine" \
  --enable-win64 \
  --enable-archs=i386,x86_64 \
  --with-ffmpeg \
  --with-gstreamer \
  --with-coreaudio \
  --without-vulkan \
  --with-sdl \
  --with-mingw="$LLVM_MINGW/bin/x86_64-w64-mingw32-clang" \
  --without-x --without-wayland --without-alsa --without-dbus --without-capi \
  --without-pulse --without-oss --without-udev --without-v4l2 --without-sane \
  --with-freetype --with-gettext --with-cups --with-opencl --with-pcap \
  --disable-tests

# Ensure our FFmpeg 7.1 headers win
perl -pi -e "s|^(CFLAGS\\s*=\\s*)|\\1-I$FFMPEG_INSTALL/include |" "$WV_BUILD/Makefile"
echo "[OK] configured"
