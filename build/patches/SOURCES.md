# Patch sources & attribution

The Wine source patches in this directory were produced with AI assistance and then built and tested
by hand. This file records where each one comes from, for license transparency. Everything here is
either a port of existing GPL/LGPL Wine-family code (same license as Wine) or original code written
against public Microsoft D3D11 / Media Foundation APIs.

| Patch | Target | What it does | Source |
|---|---|---|---|
| **0001** | `win32u` | compile guard so the tree builds without Vulkan | Original — a trivial, standard Wine build idiom for guarding a `SONAME_*` macro. Not derived from any external patch. |
| **0002** | `winegstreamer` | map the VP9/AV1 MF subtypes to GStreamer caps | **Ported from Valve's Proton** winegstreamer VP9/AV1 work, rebased onto this tree and mirroring Wine's own existing codec-caps pattern. |
| **0003** | `winegstreamer` | register a VP9 decoder MFT so games find a VP9 decoder | **Ported from Valve's Proton** winegstreamer VP9 decoder; structurally a copy of Wine's own h264 decoder MFT with VP9 input types. Registered under Microsoft's public VP9 Video Extensions CLSID. |
| **0004** | `mfplat` | fall back NV12→BGRA when the backend can't create NV12 textures | **Original (AI-generated).** Uses only the public `ID3D11Device::CheckFormatSupport` API plus a standard BGRA fallback, written for the macOS/d3dmetal NV12 texture limitation. |
| **0005** | `winegstreamer` | on macOS, the video decoder MFT reports not-D3D-aware so UE ElectraPlayer takes its software path | **Original (AI-generated)** for the macOS/d3dmetal case. |
| **0006** | `winegstreamer` | synthesize a missing AAC `AudioSpecificConfig` so the audio decoder doesn't fail | **Original (AI-generated).** |
| **0007** | `winegstreamer` | on macOS, deliver 2D / `IMF2DBuffer`-capable output samples that direct MFT consumers require | **Original (AI-generated).** |
| **0008** | `d3d9` | add the opt-in D3D9-to-DXMT video bridge handle and sidecar used by legacy VMR9 cutscene presenters | **Original (AI-assisted).** Built against Wine's public D3D9 interfaces and the existing DXMT shared-texture contract. |
| **0009** | `d3d9` | upload each presented D3D9 video surface into the D3D11/DXMT bridge texture, including format conversion and synchronization | **Original (AI-assisted).** Implements the tested CPU-visible fallback path using documented D3D9/D3D11 resource APIs. |

Ports (0002, 0003) are derivative of Valve's Proton winegstreamer work and carry the same license as
Wine. The original patches (0004–0009) implement documented Microsoft D3D / Media Foundation API
patterns for the macOS graphics-translation limitations this project targets.
