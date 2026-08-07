# Rebuilding the Wine DLLs

The patcher ships prebuilt artifacts in `patcher/payload/`. This directory documents how
they are produced from CrossOver 26.2's Wine 11.0 source. Rebuilding is only needed to
modify the Wine DLLs.

> The scripts here reflect the author's build environment (paths under
> `~/.local/winevideo`, an x86_64 Homebrew at `/usr/local`, `llvm-mingw`, and FFmpeg
> 7.1). Adapt the paths in `env.sh` to your machine.

## Toolchain

- **x86_64 Homebrew** (`/usr/local`) — all build commands run under Rosetta
  (`arch -x86_64`), since CrossOver's Wine is x86_64.
- **llvm-mingw** — PE cross-compiler for the Windows-side DLLs.
- **FFmpeg 7.1** — the era-appropriate FFmpeg for Wine 11.0 (avcodec 61, avformat 61,
  avutil 59, swscale 8); used to build/link `winedmo`. (CrossOver 26 itself ships no FFmpeg
  — its `winedmo` is a demux-only stub built without it — so this is purely a build-time
  dependency for our own DLLs, not an ABI we must match against the CX bundle.)
- A **GStreamer 1.24.x framework** bundling glib 2.74 (see
  `winegstreamer-vp9-recipe.md`).
- The **CrossOver 26.2 Wine source** tarball.

## Build steps

All under Rosetta / x86_64. Paths come from `env.sh`.

1. `./check-toolchain.sh` — verify prerequisites
2. `./stage-source.sh` — extract the CX26.2 Wine 11.0 source (+ a git baseline)
3. `./configure-wine.sh` — configure (FFmpeg + GStreamer + mingw)
4. `./make-wine.sh` — build (full build is slow the first time; pass a path to limit,
   e.g. `dlls/winegstreamer`)
5. Build the GStreamer plugins: `./build-gst-plugins.sh`
   (libgstvpx + libgstmatroska from the framework static libs)

## Source patches (`build/patches/`)

| Patch | Effect |
|-------|--------|
| `0001-win32u-vulkan-without-vulkan-guard` | build guard for `--without-vulkan` |
| `0002-winegstreamer-vp9-av1-caps` | VP9/AV1 caps mapping + decoder input types |
| `0003-winegstreamer-vp9-decoder-mft` | real VP9 decoder MFT (advertised via MFTEnumEx) |
| `0004-mfplat-d3d11-nv12-bgra-fallback` | d3dmetal NV12→BGRA fallback (no Metal abort) |
| `0005-winegstreamer-no-d3d-awareness-on-macos` | UE ElectraPlayer takes its software decode path on macOS |
| `0006-winegstreamer-aac-codec-data-double-strip` | synthesize a missing AAC AudioSpecificConfig |
| `0007-winegstreamer-2d-output-samples-macos` | deliver IMF2DBuffer-capable output samples on macOS |
| `0008-d3d9-dxmt-video-bridge-handle` | add the opt-in D3D9-to-DXMT video bridge handle and shared-texture sidecar |
| `0009-d3d9-dxmt-video-bridge-upload` | upload VMR9-presented D3D9 frames into the D3D11/DXMT bridge texture |

See `SOURCES.md` for per-patch attribution.

## Installing into a CrossOver app

`./install-vp9.sh` applies a built tree into an app + bottle (the development install).
The shippable, self-contained equivalent is `patcher/patch.sh`, which uses
`patcher/payload/` instead of a build tree.

Set `CX_APP=/path/to/CrossOver.app` before running to target a specific app; the default
is a disposable copy made with `ditto`. Never patch an original CrossOver in place —
work on a copy.

## Test harnesses

Probe sources and reusable runners live under `tests/`. Build the Windows probes
with llvm-mingw and run them through the app's `bin/wine` with
`CX_BOTTLE=<bottle>`. Always `wineserver -k` between runs.

## Notes

- Sourcing `env.sh` enables `set -euo pipefail`; relax with `set +e` in ad-hoc scripts.
- gnutls.h not found at make time → export keg-only `CPATH`/`LIBRARY_PATH` (done in
  `env.sh`).
- `libclang_rt.osx.a` not found → resolve via `xcrun clang` (not llvm-mingw's clang).
- Force FFmpeg 7.1 ahead of any newer Homebrew FFmpeg so `winedmo` links avcodec.61.
