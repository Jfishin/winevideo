# winevideo — native FFmpeg video decode for CrossOver (design spec)

- Date: 2026-06-28
- Status: approved (design); pending spec review → implementation plan
- Owner: driven by Claude (engineering); user is tester

## 1. Goal

Give CrossOver the ability to play **basically any video a game throws at it** through Windows' media frameworks, delivered as a **drag-and-drop patch** of an installed CrossOver.app. Match the *capability* of GE-Proton on Linux ("any video"), referencing GE's approach as faithfully as macOS/CrossOver allow, **without shipping a custom Wine distribution**.

North star: a drop-in "video playback replacement" for CrossOver that is the most compatible/reliable option available on macOS.

## 2. Scope

**In scope:** all video that a game routes through Windows' media frameworks —
- **Media Foundation** (`IMFSourceReader`, `IMFMediaEngine`, UE4/UE5 *MediaTextures*), and
- **DirectShow / quartz** (older titles, visual novels).

Codecs: VP9, AV1, H.264, HEVC, VC-1/WMV1/2/3, MPEG-1/2/4, MS-MPEG4, and others FFmpeg decodes. Containers: mp4/mov, mkv/webm (and odd extensions like NG4's `.msd`), asf/wmv, avi, ogg, etc.

**Out of scope (confirmed):**
- Game-engine-internal video decoders that bypass the OS media layer (Bink/`bink2w64.dll`, Smacker) and DRM-protected video. GE doesn't fix these either; they are game-by-game.
- Shipping or running a custom Wine build (compiling Wine DLLs at *build time* is fine; only drop-in DLLs are *deployed*).
- CXPatcher's model of bolting an external system `GStreamer.framework` into CrossOver (the GStreamer-dependency path we are deliberately replacing).

## 3. Background — current CrossOver 26 stack (source-verified)

CrossOver 26.0 is based on **Wine 11.0** (changelog) and ships **both** media backends:

- **`winedmo`** (`winedmo.dll` + `winedmo.so`): **demux-only**, FFmpeg `libavformat`-backed. `avformat_open_input(NULL)` content-probes, so it can demux *any* container FFmpeg supports (incl. matroska/webm), regardless of file extension. It maps codec → MF subtype (VP9 → `MFVideoFormat_VP90` already) but **never decodes** (`libavcodec` is used only for the H.264 `mp4toannexb` bitstream filter). No VideoToolbox, no hwaccel.
- **`mfsrcsnk`** (`mfsrcsnk.dll`): the MF media source built on winedmo. Registers byte-stream handlers for `.avi/.wav/.mp3` (+ MPEG4/ASF). Outputs **compressed** samples; relies on a downstream decoder MFT. **No webm/mkv/.msd handler.**
- **`winegstreamer`** + bundled GStreamer 1.24.5: registers decoder MFTs for **H.264 + AAC only**; its GStreamer byte-stream handler decodes some codecs internally via `gst-libav`/decodebin. **No VP9/AV1 caps/format/MFT code** (`wg_media_type.c`/`wg_format.c`/`video_decoder.c` have no VP9/AV1) → VP9 fails caps negotiation (`gst_caps_is_fixed` assertion → `MF_E_UNEXPECTED`).
- **Bundled `libavcodec.61`** (FFmpeg 7.1-era) is built **with** decoders for `h264,hevc,vp8,vp9,av1,wmv1/2/3,vc1,mpeg2/4,msmpeg4,...` but **`--disable-videotoolbox`** (software only). `libswscale` is bundled too.
- **`applemedia`** GStreamer plugin (VideoToolbox `vtdec`/`vtdec_hw`, AVFoundation) is shipped **`.disabled`**.

**POC results (stock CX26):** H.264, HEVC, VP8, WMV decode through Media Foundation; **VP9 and AV1 fail** at source creation (`MF_E_UNEXPECTED`). The decoders physically exist in the bundle but are unreachable because the GStreamer path can't negotiate them.

**Key insight:** the decode capability ("any video") is *already in the box* as `libavcodec`; it is simply never called for decoding. winevideo wires it up.

## 4. Architecture

Target pipeline (Media Foundation path):

```
game → Media Foundation (mfreadwrite / mfplat / MediaEngine)
     → winevideo byte-stream handler  (claims the container)
     → winedmo demux (libavformat)    (splits → compressed video packets, codec→MF subtype)
     → winevideo FFmpeg decoder MFT    (libavcodec decode → NV12)   ← the new decode
     → game receives NV12 frames
```

Three additions, all drop-in:

1. **Container byte-stream handlers** — register handlers for the containers CrossOver lacks (WebM/MKV, and arbitrary extensions like `.msd`) so they resolve to the winedmo/`mfsrcsnk` media source instead of falling through to the broken GStreamer path. winedmo already demuxes the *content* by probing, so this is primarily registration + routing.
2. **Universal FFmpeg video decoder MFT** — the core new component. A Media Foundation Transform that accepts any compressed video subtype (`MFVideoFormat_VP90`, AV1, H264, HEVC, VC1/WMV, MPEG, …) and outputs NV12, decoding via `libavcodec` (`avcodec_send_packet`/`avcodec_receive_frame`, `libswscale` for pixel conversion). Implemented in winedmo's split style: a unix-side decode module (`winedmo_decoder_*`, calling `libavcodec`) + a PE-side MFT that calls it via the Wine unixlib boundary. Ported from / referencing GE-Proton's FFmpeg decode work, adapted to Wine 11.0.
3. **Registry wiring (advertisement)** — register the decoder MFT under `MFT_CATEGORY_VIDEO_DECODER` for every supported input subtype, so **`MFTEnumEx` reports it**. This is what makes a game like NG4 believe "VP9 is supported" and launch.

DirectShow/quartz path (later milestone): wrap the same decoder as a DirectShow filter (DMO wrapper) so older titles use the identical FFmpeg decode.

### Component boundaries
- **byte-stream handlers**: input = file/byte-stream + extension/MIME; output = an `IMFMediaSource` (via winedmo). Independently testable: "does opening file X yield a media source with the right streams?"
- **winedmo decode module (unix)**: input = codec params + compressed packets; output = decoded raw frames (NV12/I420). Pure, no MF/COM. Testable in isolation.
- **decoder MFT (PE)**: input = `IMFSample` (compressed) + media types; output = `IMFSample` (NV12). Standard `IMFTransform`. Testable via `mf_probe`.

## 5. The MFTEnumEx advertisement requirement (first-class)

Some games **probe before they play**. NG4 calls `MFTEnumEx(MFT_CATEGORY_VIDEO_DECODER)`; if no VP9 MFT is reported it shows *"install Windows Media Foundation and the VP9 Codec"* and exits. Therefore:

- The decoder MFT MUST be registered/enumerable for each codec's input subtype.
- Because our MFT *actually decodes* (FFmpeg), the game's own VP9 code path runs normally — **no exe patching** (unlike the prior NG4 workaround, which bypassed VP9 to black/skip).
- "Advertised but fake" is explicitly rejected: a registered MFT that can't decode is worse than nothing (crashes/black). Advertisement and real decode ship together.

## 6. Data flow — NG4 (milestone 1) worked example

1. NG4 launches → `MFTEnumEx` → sees our VP9 decoder MFT → no error dialog, game proceeds.
2. Cutscene: game opens `Assets/Movies/X.msd` via Media Foundation.
3. winevideo `.msd` byte-stream handler → winedmo opens it, probes Matroska/WebM, exposes one **video-only VP9 Profile 0** stream as `MFVideoFormat_VP90`.
4. Source Reader inserts our FFmpeg decoder MFT (VP90 → NV12).
5. winedmo reads VP9 packets → unix decode (`libavcodec` vp9, software) → NV12 → game renders the cutscene.

## 7. Error handling & robustness

- **No crashes**: strict lifecycle on the MFT and unix decoder (init/flush/drain/destroy); null-checks on every COM/FFmpeg boundary; bounded buffers.
- **Graceful unsupported**: a codec FFmpeg can't decode returns a clean MF error, never a crash (the game then handles "no video" itself).
- **Negotiation fallback**: if the standard decoder-MFT insertion proves finicky in CrossOver's MF, the fallback is to have the media source decode internally and hand back finished NV12 frames (the model the GStreamer byte-stream handler already uses) — guaranteed frames, slightly less standard. Decision made per-milestone based on observed behavior.
- **Audio**: NG4 cutscenes are video-only; general audio decode (AAC/WMA/etc. via FFmpeg) is part of M2 for full cutscenes with sound and A/V sync.

## 8. Build & delivery

- **Build** against the CrossOver 26 source (`crossover-sources-26.2.0.tar.gz`, Wine 11.0) — reuse/adapt the toolchain cxGE already set up (`~/.local/cxge/toolchains/llvm-mingw`, x86_64 Homebrew deps). Reference GE-Proton's decode code directly.
- **Ship only** the changed/new files: `winedmo.dll`/`winedmo.so` (decode-extended), the decoder MFT DLL, `mfsrcsnk.dll` (handler registration) as needed, plus registry edits. Link against CrossOver's *bundled* FFmpeg dylibs for ABI match.
- **Deliver** as a drag-and-drop patcher that patches a **copy** of CrossOver.app (CXPatcher's model: original untouched, patched copy + isolated bottle). No custom Wine is deployed.
- Target CrossOver 26 (Wine 11.0) first; CrossOver Preview 27 (Wine 11.2) noted for later.

## 9. Milestones (each tester-validatable)

- **M1 — VP9 end-to-end (NG4).** WebM/`.msd` handler + winedmo VP9 decode (software) + decoder MFT + MFTEnumEx advertisement.
  - **Acceptance:** NG4 launches with no MF/VP9 error dialog; cutscenes play real video (not black/skipped); no crash; gameplay intact. (`mf_probe` PASS on VP9 webm/.msd first.)
- **M2 — "any video" via Media Foundation.** Generalize the decoder MFT to all codecs + register all container handlers; add audio decode + A/V sync.
  - **Acceptance:** Woo Chang (UE5 MF MediaTexture) shows video not black; DMC5 skill videos play without crashing; synthetic clips PASS across the codec/container matrix.
- **M3 — DirectShow/quartz path.** Wrap the decoder for DirectShow; validate an older/VN title.
- **M4 — VideoToolbox hardware decode.** Rebuild bundled FFmpeg with `--enable-videotoolbox` (or libavcodec VT hwaccel) for Apple GPU decode; software path stays as fallback.
- **M5 — drag-and-drop patcher + update resilience.** Package; handle re-applying across CrossOver updates.

## 10. Testing strategy

- **Synthetic, per-codec/container:** the `mf_probe.exe` harness (already built) prints detected native subtype + decode PASS/FAIL; generate clips with host ffmpeg. Run via `CX_BOTTLE=<bottle> .../bin/wine`; clean up with `wineserver -k`.
- **Real games (tester):** NG4 (VP9) → Woo Chang (UE5/MF black) → DMC5 (skill-video crash). Each milestone gated on its acceptance criteria before proceeding.
- Regression: keep the synthetic matrix + the three games as the standing test set.

## 11. Risks & unknowns

- **Build environment** (highest): producing ABI-matched CX26 DLLs on macOS. Mitigation: reuse cxGE's working toolchain; build the whole Wine tree once, iterate on the few DLLs.
- **MF decoder-MFT negotiation** in CrossOver's MF may be finicky → internal-decode fallback (§7).
- **VideoToolbox** requires rebuilding the bundled FFmpeg (shipped with VT disabled) → deferred to M4; not needed for M1 (software VP9 is trivial on an M4 Max).
- **CrossOver updates** may require per-version rebuilds → patcher re-applies; pin to Wine 11.0 for now.
- **Code signing / bundle integrity**: dropping DLLs into the bundle works for CLI launch (POC-confirmed); final patcher follows CXPatcher's patch-a-copy approach.

## 12. References

- CrossOver 26 source: `crossover-sources-26.2.0.tar.gz` → `sources/wine` (Wine 11.0), `sources/gstreamer`, etc. Target DLLs: `dlls/winedmo`, `dlls/mfsrcsnk`, `dlls/winegstreamer`.
- GE-Proton11-1 video rework (quartz→winedmo→ffmpeg): the architectural reference for FFmpeg-decode.
- Prior local work: `~/Documents/projects/Wdebug/cxGE` (ported ProtonGE patches + diag harness), `~/Documents/projects/Wdebug/NG4` (VP9 detection details, `.msd` = WebM/VP9 Profile 0 video-only; exe-patch workaround we are superseding).
- Test harness: `mf_probe.c` (this repo).
