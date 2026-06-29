# winevideo — VP9 video patch for CrossOver 26.2 (macOS, Apple Silicon)

Adds real **VP9 / VP8 / WebM / Matroska** video support to CrossOver 26.2 and
fixes the **d3dmetal "black/crash on video"** problem, so games that play video
through **Windows Media Foundation** (e.g. **Ninja Gaiden 4**) work — cutscenes
decode and the game no longer crashes or complains "VP9 codec not installed".

## What it fixes
- CrossOver ships **no** VP9 decoder and **no** WebM/Matroska support → this adds them.
- Games check "is VP9 supported?" before playing → this makes that check pass.
- On the **d3dmetal** backend, the D3D11 video texture path can't make NV12
  textures and **hard-crashes** (Metal "invalid pixelFormat") → this patch makes
  it fall back to a supported format instead of crashing.

## Requirements
- **CrossOver 26.2** (Apple Silicon). Built specifically against 26.2's Wine 11.0 /
  GStreamer 1.24.5 — other versions are not supported by this build.

## Use it
1. **Duplicate** your `CrossOver.app` (keep the original clean). E.g. copy it to
   `CrossOver-VP9.app`.
2. In Terminal:
   ```
   ./patch.sh /full/path/to/CrossOver-VP9.app
   ```
   - No bottle name → patches the app **and every existing bottle**.
   - To patch only specific bottles: `./patch.sh /path/CrossOver-VP9.app SteamBottle`
3. Launch your game with the patched app.

### Bottles
- The **app DLLs** apply to every bottle automatically (patch once).
- The **per-bottle registration** (VP9 decoder + .webm/.mkv/.msd handlers) is
  required and is stamped into each bottle by the patcher.
- Created a **new** bottle later? Just re-run with its name:
  `./patch.sh /path/CrossOver-VP9.app NewBottle` (the app part is already done).

## Undo
```
./restore.sh /full/path/to/CrossOver-VP9.app
```
Originals are backed up inside the app at `.winevideo-backup/`.

## Scope / caveats
- Covers games that use **Windows Media Foundation** for video (the common path).
- **Unreal Engine games that use ElectraPlayer** (UE's own video stack) are NOT
  covered — that's a separate decode path. Workaround for those: disable the
  startup/cutscene movies.
- Cutscene colors may look off on some titles (the d3dmetal fallback uses BGRA);
  the game running correctly is the goal. The permanent fix for NV12-on-Metal
  belongs upstream in Apple/CodeWeavers' D3D11→Metal layer.
