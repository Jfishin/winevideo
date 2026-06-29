# Architecture

How VP9 video is made to work in CrossOver 26.2 on Apple Silicon, and the macOS
packaging constraints involved.

## 1. CrossOver 26.2 media stack

CrossOver 26.2 is based on Wine 11.0 and bundles:

- **winegstreamer** + **GStreamer 1.24.5** — the *active* Media Foundation decoder.
  It demuxes and decodes via GStreamer `decodebin`, returning decoded frames to
  `IMFSourceReader`. (`winedmo` / `mfsrcsnk` exist but are dormant for these paths.)
- **FFmpeg 7.1** (libavcodec 61, libavformat 61, libavutil 59, libswscale 8).
- Graphics backends: **d3dmetal** (Apple GPTK; D3D11 + D3D12 → Metal) and DXVK.

A Media Foundation source is resolved by: scheme handler (`file:`) → byte-stream
handler (by extension, from `HKLM\…\Windows Media Foundation\ByteStreamHandlers\<ext>`)
→ `IMFMediaSource` → decoder.

## 2. The VP9 problem

Two independent gaps:

1. **No decoder.** CrossOver ships no VP9 decoder and no WebM/Matroska demuxer.
   `applemedia` (VideoToolbox) covers only H.264/HEVC/ProRes; `gst-libav` is built
   without `avdec_vp9`; there is no `libgstvpx` or `libgstmatroska`. A VP9 file fails
   source resolution with `MF_E_UNSUPPORTED_BYTESTREAM_TYPE`.

2. **No advertisement.** Games gate VP9 playback on
   `MFTEnumEx(MFT_CATEGORY_VIDEO_DECODER, input = {Video, VP90})`. Stock CrossOver
   returns 0, so the game shows "the codec needed to play VP9 format videos is not
   installed" and exits — before any decode is attempted. Making decode work is not
   enough; the decoder must also be *registered* as an enumerable MFT.

## 3. The fix — three parts

### 3a. Decoder + demuxer plugins

- **`libgstvpx`** (`vp9dec`/`vp8dec`) and **`libgstmatroska`** (`matroskademux`) are
  built from the GStreamer 1.24.13 framework's static libraries via small shims that
  export the `gst_plugin_<name>_get_desc()` symbol GStreamer 1.24 resolves at load.
- They must be built against the **same GStreamer/glib CrossOver ships** (GStreamer
  1.24, glib 2.74–2.78). Building against newer glib (2.80+) makes the libraries
  reference `g_once_init_enter_pointer`, which CrossOver's glib lacks → `dlopen` fails
  → no source for *any* codec.
- Runtime dependencies (`libvpx`, `liborc`, `libz`, `libbz2`) are bundled, and all
  Mach-O `LC_LOAD_DYLIB` compat versions are rewritten to match CrossOver's
  (GStreamer 2414→2405, glib 7401→7801) so the loader accepts them.

### 3b. winegstreamer VP9/AV1 caps

`winegstreamer.dll`/`.so` is patched (`build/patches/0002`) to map the MF subtypes
`MFVideoFormat_VP90`/`AV1` to GStreamer caps (`video/x-vp9`, `video/x-av1`), so the
internal `decodebin` pipeline can negotiate VP9. The `.so` is rebuilt against the
framework GStreamer (not Homebrew) to avoid the glib symbol mismatch above.

### 3c. VP9 decoder MFT registration

A real winegstreamer-backed VP9 decoder MFT is added (`build/patches/0003`):
`CLSID_wg_vp9_decoder` + `vp9_decoder_create` (modeled on the existing H.264 MFT;
inputs VP90/VP80, outputs NV12/I420/YV12/IYUV/YUY2) wired into `mfplat`'s
`class_objects[]`. It is registered in the bottle registry (`patcher/payload/reg/`):

- `HKLM\Software\Classes\CLSID\{…}` + `InprocServer32` → `winegstreamer.dll`
- `HKLM\Software\Classes\MediaFoundation\Transforms\<clsid>` with `InputTypes`/
  `OutputTypes`/`MFTFlags`
- category `MediaFoundation\Transforms\Categories\{d6c02d4b-…}\<clsid>`
- plus `Wow6432Node` mirrors and `.webm`/`.mkv`/`.msd` byte-stream handlers
  (CLSID `{317df618-5e5a-468a-9f15-d827a9a08162}`, the GStreamer byte-stream handler).

`MFTEnumEx` reads `HKCR\MediaFoundation\Transforms\Categories\…`; `regedit /S` is used
to import (`reg import`/`reg delete` silently no-op for these keys).

VP9 is Profile 0 / 4:2:0 (`yuv420p`). Profile 1 / 4:4:4 is not mapped.

## 4. The d3dmetal NV12 video-texture crash

Independent of VP9: any game playing video through a **D3D-backed** `IMFSourceReader`
crashes on the first frame on the d3dmetal backend.

- The decoded frame is handed to D3D11 as an **NV12** texture.
- The active D3D11→Metal layer reports `CheckFormatSupport(DXGI_FORMAT_NV12) = 0`
  (Metal has no single NV12 pixel format).
- Wine's MF sample allocator (`mfplat`) creates the texture anyway. The format maps to
  `MTLPixelFormatInvalid (0)`, and Apple's Metal validation calls `abort()`:
  `-[MTLTextureDescriptorInternal validateWithDevice:] … invalid pixelFormat (0)`.
  Wine surfaces it as `EXCEPTION_WINE_ASSERTION`. The process dies.

This is **codec-independent** — H.264 video crashes identically. DXVK (D3D11→Vulkan→
MoltenVK) handles NV12 and does not crash, but most D3D12 titles require d3dmetal.

**Fix** (`build/patches/0004`, `mfplat/sample.c`): in the sample allocator, call
`ID3D11Device_CheckFormatSupport` before `CreateTexture2D`; if the format is not
creatable, fall back to `DXGI_FORMAT_B8G8R8A8_UNORM`. The texture is then always
creatable and Metal does not abort. Some titles may show incorrect colors (the upstream
video processor's YUV→RGB handling varies); a complete fix belongs in the D3D11→Metal
backend.

## 5. macOS packaging constraints

Producing a launchable, modified CrossOver app on Apple Silicon requires working around
several macOS protections:

- **Copy with `ditto`.** Clone-based copies (`cp -c`, `FileManager.copyItem`) produced
  bundles whose binaries did not execute reliably; `ditto` produces a faithful copy.
- **Strip quarantine.** A copied/downloaded bundle carries `com.apple.quarantine`;
  Gatekeeper then `SIGKILL`s the wine binaries (`Killed: 9`). Remove it with
  `xattr -dr com.apple.quarantine`.
- **App Management (TCC).** A GUI app cannot write inside another `.app` bundle without
  the App Management privilege; the writes are silently denied. The GUI runs the
  app-file step elevated (`osascript … with administrator privileges`); a terminal with
  Full Disk Access can write directly.
- **Re-seal without `--deep`.** Modifying the bundle invalidates its code-signature seal,
  so Finder reports "damaged." Re-sign with `codesign --force --sign -` **without**
  `--deep`: this rebuilds a valid `CodeResources` over the modified contents and ad-hoc
  signs only the main executable, while the nested wine binaries keep their Developer-ID
  signatures and JIT entitlements. `--deep` would re-sign everything ad-hoc and strip
  those entitlements, after which Wine runs but silently does nothing. Renaming the seal
  aside leaves the main executable's signature referencing a missing seal — still
  "damaged."
- **Wine registry flush delay.** Registry writes (`reg add`/`regedit /S`) go to an
  in-memory store and are flushed to `system.reg` only ~5s after a change; a hard
  `wineserver -k` before the flush drops them. A brand-new bottle must also be fully
  initialized (run any command once) before its first write. The patcher initializes the
  bottle, writes the keys, then polls `system.reg` until the keys appear before shutting
  down.

## 6. Test harnesses

- `mf_probe.c` — opens a file via `MFCreateSourceReaderFromURL`, reads one decoded
  sample, prints the native subtype and a PASS/FAIL.
- `mft_probe.c` — replicates a game's capability check:
  `MFTEnumEx(VIDEO_DECODER, …)` per codec, then activates the VP9 MFT and negotiates
  VP90→NV12 to prove it is a real, instantiable decoder.
- `mf_probe_d3d.c` / `mf_probe_d3d12.c` — D3D11- and D3D12+D3D11On12-backed SourceReader
  paths, used to reproduce and verify the d3dmetal NV12 texture behavior.
- `mf_probe_tex.c` — direct `CreateTexture2D` format-support probe.

Build with llvm-mingw, e.g.:
`x86_64-w64-mingw32-gcc mft_probe.c -o mft_probe.exe -lmfplat -lmfuuid -lole32 -luuid`.
Run via the app's `bin/wine` with `CX_BOTTLE=<bottle>`.
