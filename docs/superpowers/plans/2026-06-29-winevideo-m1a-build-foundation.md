# Milestone 1A — CrossOver 26 Wine Build Foundation & Drop-in Proof — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a reproducible build of CrossOver 26's Wine 11.0 source on this Mac and prove we can rebuild `winedmo` and drop it into CrossOver with no regression — the foundation every later video task depends on.

**Architecture:** Reuse the toolchain cxGE already installed (x86_64 Homebrew at `/usr/local`, `llvm-mingw`, FFmpeg 7.1). Build the Wine tree from the CrossOver 26 source tarball with the configure flags proven on this machine for Wine 11.6. Then build a single DLL (`winedmo`), drop the matched PE+unix pair into CrossOver, and confirm via the `mf_probe` harness that decoding still works and *our* build is the one loaded.

**Tech Stack:** Wine 11.0 (CrossOver 26 source), clang + `llvm-mingw` (PE cross-compile), x86_64 Homebrew, FFmpeg 7.1, CrossOver 26 runtime, `mf_probe.exe` test harness.

**Scope note:** This plan produces a working, testable artifact (a reproducible build + a validated drop-in mechanism). It does NOT add VP9 decoding — that is the next plan (M1B), written against this build.

**Conventions used by every task:**
- Build root: `$HOME/.local/winevideo` (new; parallel to `~/.local/cxge`).
- Reused from cxGE (read-only): `~/.local/cxge/toolchains/llvm-mingw`, `~/.local/cxge/install/ffmpeg` (FFmpeg 7.1), `~/.local/cxge/src/ffmpeg`.
- Source tarball: `/Users/jfishin/Downloads/crossover-sources-26.2.0.tar.gz`.
- CrossOver app: `/Applications/CrossOver.app` (v26.0); its Wine libs: `Contents/SharedSupport/CrossOver/lib/wine/{x86_64-windows,x86_64-unix}/`.
- Test harness source: `mf_probe.c` (repo root). Test bottle: `Test`.
- All build commands run under Rosetta (`arch -x86_64`), because CrossOver's Wine is x86_64.
- Repo: `/Users/jfishin/Documents/winevideo` (git initialized).

---

### Task 1: Build scaffolding + toolchain verification

**Files:**
- Create: `build/env.sh`
- Create: `build/check-toolchain.sh`

- [ ] **Step 1: Write the shared environment file**

Create `build/env.sh`:

```bash
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
```

- [ ] **Step 2: Write the toolchain check script**

Create `build/check-toolchain.sh`:

```bash
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
chk "flex (brew)"            "[ -x $BREW_PREFIX/opt/flex/bin/flex ] || command -v flex"
chk "gstreamer pc (brew)"    "[ -e $BREW_PREFIX/opt/gstreamer/lib/pkgconfig/gstreamer-1.0.pc ]"
chk "source tarball"         "[ -f /Users/jfishin/Downloads/crossover-sources-26.2.0.tar.gz ]"
chk "CrossOver 26 app"       "[ -d $CX_APP ]"
chk "mf_probe.c"             "[ -f $(git rev-parse --show-toplevel)/mf_probe.c ]"

echo "ffmpeg libavcodec version in $FFMPEG_INSTALL:"
grep -h LIBAVCODEC_VERSION_M "$FFMPEG_INSTALL/include/libavcodec/version_major.h" 2>/dev/null | sed 's/^/  /' || echo "  (version_major.h not found)"
[ $ok -eq 1 ] && echo "ALL PRESENT" || echo "MISSING ITEMS — see Task 2 / cxGE bootstrap.sh"
```

- [ ] **Step 3: Make executable and run the check**

Run:
```bash
cd /Users/jfishin/Documents/winevideo
chmod +x build/env.sh build/check-toolchain.sh
arch -x86_64 ./build/check-toolchain.sh
```
Expected: every line prints `OK` except possibly `FFmpeg 7.1 install dir` (handled in Task 2). If `llvm-mingw` or `x86_64 Homebrew` are MISS, stop — the cxGE bootstrap did not survive; re-run `~/Documents/projects/Wdebug/cxGE/scripts/bootstrap.sh` before continuing.

- [ ] **Step 4: Commit**

```bash
cd /Users/jfishin/Documents/winevideo
git add build/env.sh build/check-toolchain.sh
git commit -m "build: add env + toolchain check scripts"
```

---

### Task 2: Ensure FFmpeg 7.1 dev libraries (ABI-match CrossOver 26)

**Why:** CrossOver 26 bundles `libavcodec.61` (FFmpeg 7.1). `winedmo` must be built against matching headers or it can crash at runtime. cxGE already built FFmpeg `release/7.1`; this task confirms it or rebuilds it.

**Files:**
- Modify: none (verification + optional rebuild using cxGE's existing script)

- [ ] **Step 1: Check whether cxGE's FFmpeg 7.1 install is usable**

Run:
```bash
cd /Users/jfishin/Documents/winevideo && source build/env.sh
ls "$FFMPEG_INSTALL/include/libavcodec/avcodec.h" "$FFMPEG_INSTALL/lib/libavcodec.a" 2>&1
cat "$FFMPEG_INSTALL/include/libavcodec/version_major.h" 2>/dev/null | grep LIBAVCODEC_VERSION_MAJOR
```
Expected: files exist and `LIBAVCODEC_VERSION_MAJOR 61`. If so, **skip to Step 3**.

- [ ] **Step 2: (Only if missing) Rebuild FFmpeg 7.1 via cxGE's script**

Run:
```bash
arch -x86_64 ~/Documents/projects/Wdebug/cxGE/scripts/build-ffmpeg.sh
```
Expected: installs to `~/.local/cxge/install/ffmpeg` with `libavcodec.61`. Re-run Step 1 to confirm.

- [ ] **Step 3: Record the FFmpeg major versions for later reference**

Run:
```bash
cd /Users/jfishin/Documents/winevideo && source build/env.sh
for h in libavcodec libavformat libavutil libswscale; do
  v=$(grep -h "${h^^}_VERSION_MAJOR" "$FFMPEG_INSTALL/include/$h/version_major.h" 2>/dev/null | awk '{print $3}')
  echo "$h major=$v"
done | tee build/ffmpeg-versions.txt
```
Expected (must match CrossOver's bundled `libav*.NN.dylib`): `libavcodec major=61`, `libavformat major=61`, `libavutil major=59`, `libswscale major=8`. If a major differs from CrossOver's bundled dylib numbers, note it — it will be addressed in the drop-in proof (Task 6).

- [ ] **Step 4: Commit**

```bash
git add build/ffmpeg-versions.txt
git commit -m "build: record FFmpeg 7.1 major versions matching CX26"
```

---

### Task 3: Stage the CrossOver 26 Wine 11.0 source

**Files:**
- Create: `build/stage-source.sh`
- Produces (gitignored): `$HOME/.local/winevideo/src/wine`

- [ ] **Step 1: Write the staging script**

Create `build/stage-source.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"; source ./env.sh
TARBALL="/Users/jfishin/Downloads/crossover-sources-26.2.0.tar.gz"

mkdir -p "$WV_ROOT/src"
if [ -d "$WV_SRC/.git" ]; then echo "Source already staged at $WV_SRC"; exit 0; fi

echo "Extracting sources/wine ..."
tmp="$WV_ROOT/src/_extract"
mkdir -p "$tmp"
tar -xzf "$TARBALL" -C "$tmp" sources/wine
mv "$tmp/sources/wine" "$WV_SRC"
rm -rf "$tmp"

cd "$WV_SRC"
git init -q -b main
git add -A
git -c user.email=build@winevideo -c user.name=winevideo commit -q -m "vendor: CrossOver 26.2.0 Wine 11.0 source (pristine)"
echo "Staged + git baseline at $WV_SRC"
cat VERSION
```

- [ ] **Step 2: Run it**

Run:
```bash
cd /Users/jfishin/Documents/winevideo && chmod +x build/stage-source.sh
arch -x86_64 ./build/stage-source.sh
```
Expected: ends with `Wine version 11.0` and a pristine git baseline in `$WV_SRC` (lets us diff our future patches cleanly).

- [ ] **Step 3: Commit the staging script**

```bash
git add build/stage-source.sh
git commit -m "build: add CX26 Wine source staging script"
```

---

### Task 4: Configure the Wine build

**Files:**
- Create: `build/configure-wine.sh` (adapted from cxGE `build-wine.sh:77-148`, no custom patches)

- [ ] **Step 1: Write the configure script**

Create `build/configure-wine.sh`:

```bash
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
```

- [ ] **Step 2: Run configure**

Run:
```bash
cd /Users/jfishin/Documents/winevideo && chmod +x build/configure-wine.sh
./build/configure-wine.sh 2>&1 | tee "$HOME/.local/winevideo/configure.log"
```
Expected: ends `[OK] configured`; a `Makefile` exists in `$HOME/.local/winevideo/build/wine`. If configure aborts with `unknown option --with-ffmpeg` (Wine 11.0 may auto-detect instead of exposing the flag), remove `--with-ffmpeg` from `configure-wine.sh` and re-run — Step 3 still verifies FFmpeg was detected.

- [ ] **Step 3: Verify FFmpeg and MinGW were detected (critical)**

Run:
```bash
cd "$HOME/.local/winevideo/build/wine"
grep -iE "ffmpeg" config.log | grep -iE "yes|found|avcodec" | tail -5
grep -iE "x86_64-w64-mingw32" config.log | tail -3
```
Expected: FFmpeg detected (avformat/avcodec found) and the MinGW cross-compiler accepted. If FFmpeg is "no", `winedmo` will be skipped — fix `PKG_CONFIG_PATH`/`CPATH` and re-run before proceeding.

- [ ] **Step 4: Commit**

```bash
cd /Users/jfishin/Documents/winevideo
git add build/configure-wine.sh
git commit -m "build: add Wine configure script (CX26 flags)"
```

---

### Task 5: Build the Wine tree and locate the target DLLs

**Files:**
- Create: `build/make-wine.sh`

- [ ] **Step 1: Write the build script**

Create `build/make-wine.sh` (the `clang_rt` flag mirrors cxGE `build-wine.sh:154-158`, needed to link Wine's unix `.so` modules on Apple Silicon cross-compile):

```bash
#!/usr/bin/env arch -x86_64 bash
set -euo pipefail
cd "$(dirname "$0")"; source ./env.sh
cd "$WV_BUILD"

SDK="$(xcrun --show-sdk-path)"
CLANG_RT="$(clang -arch x86_64 -print-file-name=libclang_rt.osx.a 2>/dev/null)"
MAKE_LDFLAGS="-arch x86_64 -Wl,-headerpad_max_install_names -Wl,-rpath,@loader_path/../lib -Wl,-rpath,$BREW_PREFIX/lib -Wl,-rpath,$FFMPEG_INSTALL/lib -isysroot $SDK -Wl,-syslibroot,$SDK $CLANG_RT"

TARGET="${1:-}"   # empty = full build; or pass e.g. dlls/winedmo
make -j"$(sysctl -n hw.ncpu)" LDFLAGS="$MAKE_LDFLAGS" $TARGET
```

- [ ] **Step 2: Run the full build (long — 30–60 min)**

Run:
```bash
cd /Users/jfishin/Documents/winevideo && chmod +x build/make-wine.sh
./build/make-wine.sh 2>&1 | tee "$HOME/.local/winevideo/build.log"
```
Expected: completes without fatal error. Warnings are fine. If it dies, capture the first error from `build.log` (search for `Error` / `error:`) and resolve before continuing — typically a missing brew dep or header path.

- [ ] **Step 3: Verify the target DLLs were produced with the right architecture**

Run:
```bash
B="$HOME/.local/winevideo/build/wine"
for f in dlls/winedmo/winedmo.dll dlls/winedmo/x86_64-unix/winedmo.so dlls/mfsrcsnk/mfsrcsnk.dll; do
  echo "--- $f ---"; file "$B/$f" 2>&1 | sed 's/^/  /'
done
```
Expected: `winedmo.dll` and `mfsrcsnk.dll` → `PE32+ executable ... x86-64`; `winedmo.so` → `Mach-O 64-bit ... x86_64`. (If `winedmo.so` path differs, find it: `find "$B" -name 'winedmo.so'`.)

- [ ] **Step 4: Commit**

```bash
cd /Users/jfishin/Documents/winevideo
git add build/make-wine.sh
git commit -m "build: add Wine make script; full baseline build succeeds"
```

---

### Task 6: Drop-in proof — rebuild `winedmo`, load it in CrossOver, no regression

**Goal of this task:** prove (a) our rebuilt `winedmo` is ABI-compatible with CrossOver 26 (H.264 still decodes), and (b) *our* binary is the one actually loaded (via a trace marker). This de-risks the entire project.

**Files:**
- Create: `build/dropin.sh`
- Modify (temporary marker): `$WV_SRC/dlls/winedmo/main.c`
- Test: `mf_probe.exe` in the `Test` bottle

- [ ] **Step 1: Write the drop-in script (with backup/restore)**

Create `build/dropin.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"; source ./env.sh
B="$WV_BUILD"
BK="$WV_ROOT/cx-backup"      # original CrossOver DLLs saved here
mkdir -p "$BK"

backup() { for rel in "wine/x86_64-windows/winedmo.dll" "wine/x86_64-unix/winedmo.so"; do
  [ -f "$BK/$(basename $rel)" ] || cp "$CX_LIB/$rel" "$BK/$(basename $rel)"; done
  echo "originals backed up in $BK"; }

install_ours() {
  cp "$B/dlls/winedmo/winedmo.dll" "$CX_WINE_PE/winedmo.dll"
  cp "$(find "$B" -name winedmo.so | head -1)" "$CX_WINE_UNIX/winedmo.so"
  echo "installed our winedmo.{dll,so} into CrossOver"; }

restore() {
  cp "$BK/winedmo.dll" "$CX_WINE_PE/winedmo.dll"
  cp "$BK/winedmo.so"  "$CX_WINE_UNIX/winedmo.so"
  echo "restored original winedmo"; }

case "${1:-install}" in
  backup) backup;;
  install) backup; install_ours;;
  restore) restore;;
  *) echo "usage: dropin.sh [backup|install|restore]"; exit 2;;
esac
```

- [ ] **Step 2: Baseline — confirm stock winedmo decodes H.264 (control)**

Run (regenerate a clip + probe; reuses the POC harness):
```bash
cd /Users/jfishin/Documents/winevideo && source build/env.sh
B="$HOME/Library/Application Support/CrossOver/Bottles/Test/drive_c/mftest"; mkdir -p "$B"
ffmpeg -hide_banner -loglevel error -y -f lavfi -i testsrc=size=256x144:rate=30:duration=1 \
  -c:v libx264 -pix_fmt yuv420p "$B/h264.mp4"
"$LLVM_MINGW/bin/x86_64-w64-mingw32-gcc" mf_probe.c -o /tmp/mf_probe.exe -lmfplat -lmfreadwrite -lmfuuid -lole32 -luuid
CX_BOTTLE=Test WINEDEBUG=-all "$CX_BIN/wine" /tmp/mf_probe.exe 'C:\mftest\h264.mp4' 2>/dev/null | grep -E "PASS|DECODED"
"$CX_BIN/wineserver" -k 2>/dev/null || true
```
Expected: `>>> DECODED ... === PASS ===`. This is the control: stock CrossOver decodes H.264.

- [ ] **Step 3: Add a load-marker trace to winedmo, rebuild just that DLL**

Edit `$WV_SRC/dlls/winedmo/main.c` — find the `winedmo_demuxer_create` PE entry (the function called when MF opens a file) and add one line at its top:

```c
    ERR("winevideo-build winedmo loaded (drop-in proof)\n");
```

(If `ERR` needs the channel, it is already declared via `WINE_DEFAULT_DEBUG_CHANNEL` in this file. Use `ERR` so it prints even at `WINEDEBUG=-all`.)

Rebuild only winedmo:
```bash
cd /Users/jfishin/Documents/winevideo
./build/make-wine.sh dlls/winedmo
```
Expected: incremental build succeeds; `winedmo.dll`/`winedmo.so` updated (newer mtime).

- [ ] **Step 4: Install our winedmo into CrossOver and probe**

Run:
```bash
cd /Users/jfishin/Documents/winevideo
./build/dropin.sh install
CX_BOTTLE=Test WINEDEBUG=-all "$CX_BIN/wine" /tmp/mf_probe.exe 'C:\mftest\h264.mp4' 2>&1 | grep -E "winevideo-build|PASS|DECODED|err:"
"$CX_BIN/wineserver" -k 2>/dev/null || true
```
Expected BOTH:
1. `winevideo-build winedmo loaded (drop-in proof)` appears → **our** binary is loaded.
2. `>>> DECODED ... === PASS ===` → **no regression**; ABI-compatible.

If (1) is missing: the file did not get picked up (check paths / wineserver was stale → re-run `wineserver -k`). If (2) regresses (crash/FAIL): ABI mismatch — inspect `otool -L "$CX_WINE_UNIX/winedmo.so"` for FFmpeg `install_name`s pointing outside CrossOver; if so, add an `install_name_tool -change` step in `dropin.sh` to repoint them at `$CX_LIB64/libav*.dylib`, and re-test. Document the resolution in `build/README.md` (Task 7).

- [ ] **Step 5: Restore stock winedmo, remove the marker**

```bash
cd /Users/jfishin/Documents/winevideo
./build/dropin.sh restore
cd "$HOME/.local/winevideo/src/wine" && git checkout dlls/winedmo/main.c
```
Expected: CrossOver back to stock; marker removed from source. (The proof is recorded; we don't keep the marker.)

- [ ] **Step 6: Commit the drop-in tooling**

```bash
cd /Users/jfishin/Documents/winevideo
git add build/dropin.sh
git commit -m "build: add drop-in install/restore; winedmo rebuild loads in CX26 with no regression"
```

---

### Task 7: Document the foundation

**Files:**
- Create: `build/README.md`
- Modify: `.gitignore` (ignore the external build root note)

- [ ] **Step 1: Write `build/README.md`**

Create `build/README.md`:

```markdown
# winevideo build foundation

Reproducible build of CrossOver 26's Wine 11.0 + drop-in of rebuilt DLLs.

## One-time
- Toolchain comes from cxGE: x86_64 Homebrew (/usr/local), llvm-mingw and FFmpeg 7.1
  under ~/.local/cxge. If missing, run ~/Documents/projects/Wdebug/cxGE/scripts/bootstrap.sh.

## Build steps (all under Rosetta)
1. ./build/check-toolchain.sh      # verify prerequisites
2. ./build/stage-source.sh         # extract CX26 Wine 11.0 to ~/.local/winevideo/src/wine
3. ./build/configure-wine.sh       # configure (FFmpeg + GStreamer + mingw)
4. ./build/make-wine.sh            # full build (30-60 min); or pass a target e.g. dlls/winedmo
5. ./build/dropin.sh install       # copy built winedmo.{dll,so} into CrossOver (backs up originals)
   ./build/dropin.sh restore       # revert CrossOver to stock

## Test
CX_BOTTLE=Test wine /tmp/mf_probe.exe 'C:\mftest\<clip>'   # PASS/FAIL + detected codec
Always `wineserver -k` between runs.

## Notes
- FFmpeg majors must match CX26: avcodec 61, avformat 61, avutil 59, swscale 8.
- Build root ~/.local/winevideo is outside the repo (not committed).
- [Drop-in proof result / any install_name fixes documented here.]
```

- [ ] **Step 2: Commit**

```bash
cd /Users/jfishin/Documents/winevideo
git add build/README.md
git commit -m "build: document the build + drop-in workflow"
```

---

## Definition of done (M1A)

- `./build/check-toolchain.sh` → all present.
- Full Wine build completes; `winedmo.{dll,so}` and `mfsrcsnk.dll` produced as x86_64.
- `dropin.sh install` → CrossOver loads **our** winedmo (marker seen) and H.264 still decodes (`mf_probe` PASS).
- `dropin.sh restore` → CrossOver back to stock.
- All scripts committed; `build/README.md` documents the workflow and any `install_name` fix.

**Next plan (M1B):** add a WebM/`.msd` byte-stream handler + an FFmpeg VP9 decoder MFT (advertised via `MFTEnumEx`), written against this working build, validated on synthetic VP9 then Ninja Gaiden 4.
