# winevideo build foundation

Reproducible build of CrossOver 26's Wine 11.0, plus drop-in of rebuilt DLLs into a
CrossOver app, for developing native video decode.

## One-time toolchain (reused from cxGE)
x86_64 Homebrew (`/usr/local`), `llvm-mingw`, and FFmpeg **7.1** live under `~/.local/cxge`.
If missing, run `~/Documents/projects/Wdebug/cxGE/scripts/bootstrap.sh`.
FFmpeg majors MUST match CrossOver 26: avcodec 61, avformat 61, avutil 59, swscale 8.

## Build steps (all under Rosetta / x86_64)
1. `./build/check-toolchain.sh`   — verify prerequisites
2. `./build/stage-source.sh`      — extract CX26.2 Wine 11.0 → `~/.local/winevideo/src/wine` (+ git baseline)
3. `./build/configure-wine.sh`    — configure (FFmpeg + GStreamer + mingw)
4. `./build/make-wine.sh`         — full build (~30-60 min first time). Pass a path to limit, e.g. `dlls/winedmo`
5. `./build/dropin.sh install`    — copy built winedmo.{dll,so} into `$CX_APP`, repoint FFmpeg to its bundle, ad-hoc sign
   `./build/dropin.sh restore`    — revert that app to stock

## Test target
`$CX_APP` defaults to a **disposable copy** of CrossOver 26.2 at
`~/.local/winevideo/CrossOver-test.app` (made with `ditto` from the user's real 26.2).
Never modify the user's real apps:
- real 26.2 (used): `/Users/jfishin/UltimateLauncher/tools/CrossOver.app`
- 26.0: `/Applications/CrossOver.app`
Override with `CX_APP=/path/to/CrossOver.app` before sourcing if needed.

## Probe (regression / smoke test)
`mf_probe.c` (repo root) → compile with llvm-mingw; run via the app's `bin/wine`:
```
CX_BOTTLE=Test <app>/Contents/SharedSupport/CrossOver/bin/wine /tmp/mf_probe.exe 'C:\mftest\<clip>'
```
Always `wineserver -k` between runs (wine hangs easily).

## First-build gotchas already fixed (in env.sh / make-wine.sh)
- gnutls.h not found → export keg-only include/lib paths (`CPATH`/`LIBRARY_PATH`) at make time.
- `libclang_rt.osx.a` not found → resolve via `xcrun clang` (not llvm-mingw's clang).
- `SONAME_LIBVULKAN` undefined (`--without-vulkan`) → guard patch (`build/patches/0001-*`).
- FFmpeg 8.x picked over 7.1 → force FFmpeg-7.1 paths FIRST so winedmo links avcodec.61 (ABI match).
- Sourcing `env.sh` enables `set -euo pipefail`; relax with `set +e` in ad-hoc test scripts.

## IMPORTANT architecture finding (read before M1B)
See `docs/superpowers/notes/2026-06-29-cx26-routing-findings.md`. Short version: in CrossOver 26,
**winegstreamer (GStreamer) is the active Media Foundation decoder; winedmo/mfsrcsnk are dormant.**
This reshapes the VP9 plan.
