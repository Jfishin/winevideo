# winevideo patcher — VP9 video for CrossOver 26.2 (macOS, Apple Silicon)

Adds **VP9 / VP8 / WebM / Matroska** video support to CrossOver 26.2 and fixes the
d3dmetal crash on Media Foundation video, so games that play VP9 cutscenes work.

## What it does

- Adds a VP9/VP8 decoder + WebM/Matroska demux to CrossOver's media pipeline.
- Registers a VP9 decoder MFT so games' "is VP9 supported?" check passes.
- Patches `mfplat` so the d3dmetal D3D11 path falls back to a supported texture format
  instead of crashing (`invalid pixelFormat (0)`).

See `../docs/ARCHITECTURE.md` for details.

## Requirements

CrossOver **26.2**, Apple Silicon. The binaries are built against 26.2's Wine 11.0 /
GStreamer 1.24.5 and are version-specific.

## GUI

Open `../gui/winevideo Patcher.app` (build it with `../gui/build-app.sh` if needed):

1. Drag your `CrossOver.app` in → it duplicates to `~/Applications/CrossOver-winevideo.app`.
2. Click **Scan bottles** and tick the bottle you play your VP9 game in (required — games
   gate on the per-bottle VP9 decoder MFT, so the bottle must be patched too).
3. Click **Patch app** and authenticate (writing inside an app bundle needs elevation).
   This patches the app **and** the selected bottle(s) together.
4. Launch `~/Applications/CrossOver-winevideo.app`.

Clear quarantine on the unsigned patcher app before first launch:
`xattr -cr "../gui/winevideo Patcher.app"`.

## Command line

Patch a **copy** of CrossOver:

```sh
# duplicate first, e.g.:  ditto /Applications/CrossOver.app ~/Applications/CrossOver-winevideo.app
./patch.sh /full/path/to/CrossOver-copy.app            # app + every existing bottle
./patch.sh /full/path/to/CrossOver-copy.app SteamBottle  # app + only this bottle
```

`patch.sh` also accepts `--app-only` / `--bottle-only` to run a single phase (the GUI
uses these to run the app step elevated and the bottle step as the user).

After patching, the app is de-quarantined and re-sealed (ad-hoc) so it launches normally.

### Bottles

- The **app-level DLLs** apply to every bottle automatically (patch once).
- The **per-bottle registration** (VP9 decoder MFT + `.webm`/`.mkv`/`.msd` handlers) must
  be applied to each bottle. Re-run with a bottle's name for bottles created later.
- Patch a bottle after the game is installed (so the bottle is initialized). The patcher
  prints `VP9 decoder MFT registered ✓` or a warning to re-run.

## Undo

```sh
./restore.sh /full/path/to/CrossOver-copy.app [bottle ...]
```

Originals are backed up alongside the app at `<app>.winevideo-backup/`.

## Scope and limitations

- Covers games using **Windows Media Foundation** (`IMFSourceReader`).
- **Unreal Engine titles using ElectraPlayer** are not covered (separate video stack);
  workaround is to disable the game's startup/cutscene movies.
- The NV12→BGRA fallback may render some cutscenes with off colors; the game running
  without crashing is the goal.
