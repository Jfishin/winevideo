# CrossOver 26 media-routing findings (and what they mean for the VP9 plan)

Date: 2026-06-29 (overnight autonomous session)
Status: **decision needed from user** before M1B implementation

## TL;DR

The build foundation (M1A) works. But while proving the drop-in, I discovered that the
**premise of Route A is not how CrossOver 26 actually behaves at runtime**:

- **winegstreamer (GStreamer) is the *active* Media Foundation decoder in CX26.** It demuxes
  AND decodes via GStreamer `decodebin`/`gst-libav`, returning already-decoded frames.
- **winedmo / mfsrcsnk are dormant** — never loaded for the files I tested.
- Containers with no GStreamer handler (`.webm`, `.mkv`, `.avi`) → `MF_E_UNEXPECTED` "no source".
- **VP9/AV1 fail** because winegstreamer has no VP9/AV1 caps mapping (and the container often
  has no byte-stream handler at all).

This means Route A ("route everything through winedmo+FFmpeg, GE to the tee") requires *activating
a dormant pipeline AND building a decoder*, whereas the GStreamer path is already decoding
everything except VP9/AV1. **This revisits the Route A vs winegstreamer decision — your call.**

## What M1A proved (solid)

- Reproducible build of CX26.2 Wine 11.0 on this Mac (`build/*.sh`), first-build gotchas fixed.
- Our rebuilt `winedmo.{dll,so}` + `mfsrcsnk.dll` are **ABI-correct**: winedmo.so links
  `libavcodec.61 / libavformat.61 / libavutil.59` (CX26's exact FFmpeg 7.1; cxGE's copy is the
  identical build CrossOver ships).
- Drop-in mechanism works: `dropin.sh` installs our DLLs into a CrossOver app, repoints FFmpeg
  install-names to that app's bundled libs, ad-hoc signs, and restores. **No regression**:
  H.264 still decodes with our winedmo installed; no crash.

## The evidence (how I know winedmo is dormant)

Tested against a disposable copy of the user's CrossOver **26.2** (matching the 26.2.0 source we
build from), bottle `Test`, probe = `mf_probe.exe`:

| File | Result | Routing |
|---|---|---|
| `h264.mp4` | DECODED, native subtype reported as **NV12** (already decoded) | GStreamer `decodebin` decodes internally; winedmo not involved |
| `vp9.webm` | `CreateSourceReader=0xC00D36BB` NO SOURCE | no byte-stream handler for webm |
| `test.avi` | `CreateSourceReader=0xC00D36BB` NO SOURCE | no working handler |

- winedmo's `DllMain` has a `TRACE` (in CX source). With `WINEDEBUG=+dmo` it **never printed** →
  winedmo.dll was never loaded for any test file.
- Even after dropping in our **trace-enabled** winedmo + mfsrcsnk, no winedmo/mfsrcsnk traces
  appeared (and stock CX DLLs are release builds with TRACE compiled out — limited visibility).
- Bottle registry: **winegstreamer ~36 references vs mfsrcsnk ~8**; the broad byte-stream handler
  `@="C:\\windows\\system32\\winegstreamer.dll"`.

Caveat: the `Test` bottle was created by CX 26.0. A fresh 26.2 bottle *might* register mfsrcsnk's
handlers differently — not yet tested (bottle creation is hang-prone; deferred). Also `vp9.webm`
earlier (on 26.0/`/Applications`) reached a GStreamer `gst_caps_is_fixed` assertion rather than
NO SOURCE — so webm routing is bottle-dependent and still a bit murky.

## What this means for the two routes

**Route A — winedmo/FFmpeg (your earlier pick, "GE to the tee"):**
Needs all of: (1) register byte-stream handlers so VP9 containers (`.webm/.mkv/.msd`) resolve to
mfsrcsnk's winedmo-backed source; (2) **add a decoder** — winedmo is demux-only, so build an
FFmpeg-backed VP9 decoder MFT (or make the source decode internally); (3) MFTEnumEx advertisement.
This is building+activating a parallel pipeline next to the one that already works. Most faithful
to GE-Proton11's newest design, but the largest effort.

**Route B — winegstreamer caps (what cxGE did; GE's MF-patch era):**
GStreamer is already the live decoder for H.264/HEVC/VP8/WMV. To add VP9/AV1: (1) byte-stream
handler for `.webm/.mkv/.msd`; (2) add VP9/AV1 caps+format+decoder-type to winegstreamer
(`wg_media_type.c`, `wg_format.c`, `video_decoder.c`, `mfplat.c`); (3) the decoders already exist
in the bundle — `gst-libav`'s `avdec_vp9` (software) and `applemedia`'s `vtdec` (Apple VideoToolbox
HW, shipped **disabled**). Smaller, matches how CX26 actually works, and is literally GE's MF-patch
approach. cxGE got MFTEnumEx enumeration working this way but never confirmed full VP9 *playback*.
Its patches `0001`/`0002` **do not apply cleanly to Wine 11.0** (written for 11.6) — need porting.

## Recommendation

Lean **Route B** (or hybrid): it targets the pipeline that's already doing the work, needs no
new decoder (reuse gst-libav / VideoToolbox), and is the shorter path to "VP9 actually plays."
Route A remains the long-term GE-faithful ideal if we want to be fully off GStreamer. **Either way,
M1B = container-handler + VP9 caps/decoder + advertisement; the difference is which backend decodes.**

This is a genuine fork that changes the plan, so I stopped here rather than hand-port a decode
backend overnight against your earlier Route A choice.

## Decisive next experiment (when approved)

Port cxGE `0001`/`0002` to Wine 11.0 → add a `.webm/.mkv/.msd` byte-stream handler → rebuild
winegstreamer.dll/.so → test `vp9.webm` on a **fresh 26.2 bottle**, first via `avdec_vp9`
(software), then with `applemedia` enabled (VideoToolbox HW). If VP9 decodes → Route B confirmed
and NG4 is in reach.

## Safety / cleanup state
- Real apps untouched (26.0 and 26.2 both stock).
- Test copy: `~/.local/winevideo/CrossOver-test.app` (disposable; currently has our trace DLLs).
- Build tree: `~/.local/winevideo` (gitignored; source tree has vulkan guard patch committed).
