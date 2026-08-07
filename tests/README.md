# Tests and probes

This directory contains reusable validation material for winevideo.

- `integration/` contains shell-level patcher, packaging, and configuration
  checks.
- `probes/media-foundation/` contains focused Windows Media Foundation probes.
- `probes/d3d9-bridge/` contains the DXMT shared-handle and D3D9 pixel-transfer
  probes used to qualify the video bridge.
- `scripts/` contains portable build and logging helpers.

## Run the automated checks

```sh
for test_script in tests/integration/*.sh; do
  bash "$test_script"
done
```

## Build the D3D9 bridge probes

Install or select an x86_64 MinGW compiler, then run:

```sh
WINEVIDEO_MINGW_CC=/path/to/x86_64-w64-mingw32-gcc \
  tests/scripts/build-d3d9-bridge-probes.sh
```

Generated executables are written to `tests/.build/probes/` and are not tracked.
Other compiled probe binaries belong under that same build directory. Captured
probe logs belong under `tests/logs/`; both locations are ignored by Git.

## Capture a bridge trace

Run `tests/scripts/log-d3d9-video-bridge.command` and enter the bottle name and
Steam AppID when prompted. It defaults to the patched app at
`~/Applications/CrossOver-winevideo.app`. Every value can instead be supplied
through `WINEVIDEO_CROSSOVER_APP`, `WINEVIDEO_BOTTLE`,
`WINEVIDEO_STEAM_APP_ID`, and `WINEVIDEO_LOG_ROOT`.

The logger records bridge creation, frame uploads, completion failures, invalid
handles, DXGI errors, and clean surface destruction. Logs are generated outside
the repository by default.
