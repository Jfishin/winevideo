# UE5 / ElectraPlayer on CrossOver — diagnosis notes and dead ends

Field notes from a full debugging session on **Beast of Reincarnation** (Unreal Engine
5.4.4, cooked D3D12/SM6 only) on macOS 27, Apple M5 Max, CrossOver 26.3, `d3dmetal`
backend with Apple GPTK 4.0 beta 2.

The session happened **before** winevideo was found, and independently arrived at the
same root cause this project fixes. It is written down here because the project is
AI-generated and AI-assisted: an agent that reads only the fix will happily re-explore
every dead end listed below. Each one was measured, not guessed, and each one cost real
time.

Everything below is reproducible on a stock CrossOver install.

---

## 1. Symptom

3D, menus and gameplay run perfectly. Cutscenes play as a **black screen with no audio**,
the game does not crash, and progression is blocked because the story gates on them.

---

## 2. The chain, as measured

The game imports `MF.dll`, `MFPlat.dll`, `MFReadWrite.dll` and ships ElectraPlayer
(threads `ElectraPlayer::MP4 streamer`, `::Video decoder`, `::Audio decoder`).

Traced with `cxstart --debugmsg "+mfplat" --cx-log <file>`:

- `MFTEnumEx(MFT_CATEGORY_VIDEO_DECODER, MFVideoFormat_H264)` → Wine's `h264_decoder`.
- Video: H.264 1920x1080 @ 29.97 fps. Audio: AAC 5.1 48 kHz.
- Unreal creates an `IMFDXGIDeviceManager`, calls `MFCreateVideoSampleAllocatorEx`,
  `sample_allocator_SetDirectXManager`, then `InitializeSampleAllocatorEx(10, 10)` with an
  **NV12** media type, then `dxgi_device_manager_OpenDeviceHandle`,
  `GetVideoService(ID3D11Device)`, `MFCreateTrackedSample`.
- The bottle's `system32/d3d11.dll` is **Wine's own** (425 552 bytes), not DXMT's and not
  DXVK's, so on `d3dmetal` the D3D11 video device is Wine d3d11 backed by D3DMetal.

Two independent walls follow.

**Wall 1 — Wine never offers NV12.** `transform_GetOutputAvailableType` in
`winegstreamer.dll` skips it explicitly (`Skipping NV12 output format`). Unmodified, the
game therefore negotiates **I420** and shows nothing. On CrossOver 26.3 the skip is a
`je +0x20` (`74 20`) at RVA `0x2c6be`.

**Wall 2 — no graphics layer can create the texture.** With NV12 unblocked:

| Backend | Behaviour |
|---|---|
| `dxmt` | `CreateMTLTextureDescriptorInternal: creating a texture of invalid format: 103` (103 = `DXGI_FORMAT_NV12`), twenty times per playback. DXMT's `d3d11.dll` contains **zero** occurrences of `PlaneSlice`, so it has no planar texture support at all. |
| `d3dmetal` | No graphics error at all, but the process hangs forever right after `MFCreateTrackedSample`, CPU falls to 0 %. |

---

## 3. Useful measurement tricks

**Tell "waiting" from "rendering" without looking at the screen.** A hung Electra playback
sits at ~0 % CPU; a healthy game sits at 100–400 %. `ps -o %cpu= -p <pid>` sampled twice,
8 s apart, is enough to classify a black screen without asking a human.

**Get the engine's own fatal error out of a shipping build.** Shipping UE builds strip
logging, but `LowLevelFatalError` still goes through `OutputDebugString`. Running with
`--debugmsg "+seh"` and grepping the log for `OutputDebugString` reconstructs it, including
the crashing thread name.

**Do not measure liveness with `+mfplat` enabled.** That channel writes millions of lines
and freezes the game **by itself**, including on a completely stock install. Several early
"it hangs" conclusions in this session were artefacts of the tracer, not of the change
under test. Use `GST_DEBUG=1` or `2` instead, which is cheap.

**Watch frames actually being handed over.** With `GST_DEBUG=2`, a working playback prints
`wg_transform.c:read_transform_output_video: Copied 3133440 bytes` once per frame
(1920x1088 NV12). Zero of those lines means the problem is upstream of the handover; many
of them with a black screen means it is downstream.

**DXMT has a debug log**: `DXMT_LOG_LEVEL=debug`. D3DMetal has `D3DM_LOGLEVEL_INFO=1` and
`D3DM_NOT_IMPLEMENTED=1`. Both write to the process stderr, so redirect the launcher.

**Environment variables must be set on the Unix side.** CrossOver's *Run with Options* and
`cxstart --env` push variables into the **Windows** environment; GStreamer runs on the macOS
side and never sees them. `export` before launching the shortcut instead. A silent, empty
`GST_DEBUG_FILE` is the tell.

---

## 4. Dead ends — do not re-explore

All of these were tried and measured on the setup above. None makes the picture appear.

| # | Attempt | Measured result |
|---|---|---|
| 1 | Patch out the NV12 skip in `winegstreamer` (2 bytes at RVA `0x2c6be`) | NV12 is negotiated, then the game hangs at 0 % CPU before reaching the menus. Necessary but far from sufficient. |
| 2 | Reorder `h264_decoder_output_types` (RVA `0x4d4e0`) to put YUY2 first | Unreal enumerates the whole list and picks NV12 regardless. Format order is not a lever. |
| 3 | Neutralise `sample_allocator_SetDirectXManager` in `mfplat` (3 bytes at RVA `0x281e0`, `xor eax,eax; ret`) to force system-memory buffers | Game starts, then crashes in thread `ElectraPlayer::Video decoder`, `EXCEPTION_ACCESS_VIOLATION` reading `0x0`. Disassembly shows a `QueryInterface` for IID `a06eb39a-50da-425b-8c31-4eecd6c270f3` whose HRESULT is **not checked** before the pointer is dereferenced. Patch `0007` explains it: Electra requires `IMF2DBuffer` on video frames, and a plain caller-provided memory buffer does not implement it. |
| 4 | `-dx11` on the command line | No effect; the title is cooked SM6 only. |
| 5 | Disable Media Foundation entirely (`WINEDLLOVERRIDES` for `mfplat,mf,mfreadwrite,winegstreamer`) | No effect on the black screen. |
| 6 | User `Game.ini` clearing `StartupMovies` | No effect. |
| 7 | `sg.ResolutionQuality` 0 → 100 | No effect. |
| 8 | `CX_GRAPHICS_BACKEND=dxvk` | Game crashes at startup: DXVK provides D3D9–11 only, the title is D3D12. |
| 9 | Hybrid: DXVK's `d3d11.dll` copied into the bottle while D3D12 stays on D3DMetal | Game runs, picture still black. |
| 10 | Official GStreamer + `GST_PLUGIN_PATH` alone | Every plugin is rejected: `has incompatible version (plugin: 1.28, gst: 1.24)`. |
| 11 | Same, plus `DYLD_LIBRARY_PATH` at the framework so the 1.28 **core** loads too | Plugins load (0 rejections, confirmed by the `aacparse` error moving from `gstaacparse.c:358` to `:355`), `avdec_h264`/`avdec_aac` available and ranked MAX. Picture still black. |
| 12 | Rank `aacparse:NONE` to bypass the AAC parser | `Need codec_data for raw AAC` disappears, Wine can no longer build the audio transform at all, picture still black. **Audio is not the blocker.** |
| 13 | Homebrew `gst-libav` | Unusable: CrossOver's Wine runs **x86_64**, Homebrew on Apple Silicon ships **arm64**. `dlopen` fails with `incompatible architecture`. Only the official universal package works. |

Two side observations worth keeping:

- The AAC media type carries only **12 bytes** of `MF_MT_USER_DATA`, i.e. the `HEAACWAVEINFO`
  struct with no `AudioSpecificConfig` after it, which is why `aacparse` legitimately
  refuses with `Need codec_data for raw AAC`. It is noisy but harmless.
- Wiping `%LOCALAPPDATA%\<Project>\Saved` (config + `PCD3D_SM6` pipeline cache) cured an
  unrelated hard boot crash. Worth trying before blaming anything else, but keep
  `SaveGames` aside first.

---

## 5. Which patches actually carry an Electra title

Worth spelling out, because the obvious guess is wrong. For an H.264/Electra title the
`mfplat` NV12 → BGRA fallback (`0004`) is a safety net that may never even fire: once
`0005` refuses the D3D device manager, no D3D texture is ever allocated. The two patches
that carry the title are `0005` and `0007`, with `0006` cleaning up the audio track.

| Patch | File | Effect on an Electra title |
|---|---|---|
| `0002`, `0003` | `wg_media_type.c`, `video_decoder.c` | VP9 only, not involved. |
| `0004` | `mfplat/sample.c` | Safety net for the `IMFSourceReader` path. Not the mechanism here. |
| **`0005`** | `winegstreamer/video_decoder.c` | **Decisive.** Three changes: NV12 becomes enumerable again *only when no D3D manager is set* (narrowing CW HACK 26265); `MFT_MESSAGE_SET_D3D_MANAGER` returns `E_NOTIMPL` on macOS; `MF_SA_D3D_AWARE` / `MF_SA_D3D11_AWARE` are advertised as FALSE on macOS. Electra therefore takes its software path from the start. |
| **`0007`** | `winegstreamer/video_decoder.c` | **Decisive.** Sets `MFT_OUTPUT_STREAM_PROVIDES_SAMPLES` on macOS so the decoder supplies its own samples, whose buffers implement `IMF2DBuffer`. Electra requires that interface on video frames and silently rejects every frame without it. |
| **`0006`** | `winegstreamer/wg_format.c` | Fixes the AAC `codec_data` double strip, i.e. the `Need codec_data for raw AAC` error above. |

Read against that table, every dead end in section 4 is **half of the real fix applied at
the wrong layer**. Hand-clearing the NV12 skip is `0005` without its two other changes, so
NV12 also becomes available on the D3D path and the game hangs. Neutralising
`sample_allocator_SetDirectXManager` in `mfplat` is `0005`'s `E_NOTIMPL` one layer too low,
and without `0007` the resulting plain memory buffers have no `IMF2DBuffer`, which is
exactly the `QueryInterface` returning `NULL` in the crash of dead end 3.

Plus the per-game `Engine.ini` with `Electra.Win.H264UseOldOutputPath=1`, which puts Electra
on its CPU output path.

Verified end to end on Beast of Reincarnation: cutscenes play, `read_transform_output_video`
fires hundreds of times per scene, no crash, progression unblocked.

**Keep `Engine.ini` read-only.** Unreal rewrites `Saved/Config/Windows` and can delete an
`Engine.ini` it did not create. The failure mode is confusing: the first cutscene plays, and
the *next* launch crashes, which reads like the patch being unstable. `chmod 444` on the file
after creating it removes the problem entirely.
