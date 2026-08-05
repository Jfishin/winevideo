# Working and broken games

`patcher/patch.sh` already points here, so this file starts the list. Please add your own
results: engine, backend, and the exact per-game setup that was needed.

## Working

| Game | Engine / video path | CrossOver | Setup needed |
|---|---|---|---|
| Ninja Gaiden 4 | VP9-in-WebM through Media Foundation | 26.2 | Patcher only (reference title of this project). |
| Beast of Reincarnation | Unreal Engine 5.4.4, ElectraPlayer, H.264 + AAC 5.1, cooked **D3D12/SM6 only** | **26.3** | Patcher, plus the per-game `Engine.ini` with the Electra cvars, **kept read-only** (see below). Backend `d3dmetal` with Apple GPTK 4.0 beta 2. GStreamer 1.24.13 installed, so the patcher also pulled the FFmpeg decoders. |

### Beast of Reincarnation — exact recipe

```sh
# 1. patch a copy of CrossOver, plus the bottle
patcher/patch.sh /path/to/CrossOver-copy.app "Beast of Reincarnation"

# 2. per-game Engine.ini, inside the bottle
C="$HOME/Library/Application Support/CrossOver/Bottles/Beast of Reincarnation/drive_c/users/crossover/AppData/Local/BeastOfReincarnation/Saved/Config/Windows"
printf '[SystemSettings]\r\nElectra.Win.H264UseOldOutputPath=1\r\nElectra.Win.H265UseOldOutputPath=1\r\n' > "$C/Engine.ini"

# 3. THIS STEP MATTERS: Unreal deletes the file otherwise
chmod 444 "$C/Engine.ini"
```

Without step 3 the first cutscene plays, Unreal rewrites `Saved/Config/Windows` on exit and
removes `Engine.ini`, and the *next* launch crashes on the NV12 texture path. It looks like
an unstable patch; it is only the missing file.

Note on versions: the patcher's guard checks for `lib64/gstreamer-1.0` rather than the
CrossOver version string, and it applies cleanly to **26.3** as well as 26.2.

## Notes for UE5 / Electra titles in general

See [docs/UE5-ELECTRA-DIAGNOSIS.md](docs/UE5-ELECTRA-DIAGNOSIS.md) for the measured chain,
the reproducible measurement tricks, and a table of thirteen approaches that were tried and
do **not** work, so they do not get re-explored.
