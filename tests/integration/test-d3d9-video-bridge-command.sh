#!/bin/bash
set -eu

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
LOGGER="$PROJECT_ROOT/tests/scripts/log-d3d9-video-bridge.command"

if [ ! -f "$LOGGER" ]; then
  echo "FAIL: logger is missing: $LOGGER" >&2
  exit 1
fi

bash -n "$LOGGER"

for required in \
  'WINEVIDEO_CROSSOVER_APP' \
  'WINEVIDEO_BOTTLE' \
  'WINEVIDEO_STEAM_APP_ID' \
  '+timestamp' \
  '+d3d9' \
  '+quartz' \
  '+winegstreamer' \
  'd3d9-video-bridge: uploaded frame' \
  'd3d9-video-bridge: upload completion failed' \
  'Invalid shared handle' \
  'DXGI_ERROR'; do
  grep -Fq -- "$required" "$LOGGER" || {
    echo "FAIL: logger does not contain required contract: $required" >&2
    exit 1
  }
done

grep -Fq 'graphics_backend=' "$LOGGER"
if grep -Fq 'd3d9_override' "$LOGGER"; then
  echo "FAIL: logger contains an obsolete override check" >&2
  exit 1
fi

TEST_ROOT="$(mktemp -d /private/tmp/nioh-logger-test.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT

WINEVIDEO_LOG_DRY_RUN=1 \
WINEVIDEO_LOG_ROOT="$TEST_ROOT/logs" \
WINEVIDEO_CROSSOVER_APP="/Applications/CrossOver-winevideo.app" \
WINEVIDEO_BOTTLE="TestBottle" \
WINEVIDEO_STEAM_APP_ID="123456" \
bash "$LOGGER" >"$TEST_ROOT/output.txt"

grep -Fq 'DRY RUN: Steam and the selected app were not launched.' "$TEST_ROOT/output.txt"
grep -Fq 'bottle=TestBottle' "$TEST_ROOT/output.txt"
grep -Fq 'appid=123456' "$TEST_ROOT/output.txt"

ENV_FILE="$(find "$TEST_ROOT/logs" -name bridge.env.txt -type f -print -quit)"
test -n "$ENV_FILE"
grep -Fq 'cx_app=/Applications/CrossOver-winevideo.app' "$ENV_FILE"
grep -Fq 'bottle=TestBottle' "$ENV_FILE"
grep -Fq 'appid=123456' "$ENV_FILE"

echo 'PASS: portable D3D9 video bridge logger contract and dry run'
