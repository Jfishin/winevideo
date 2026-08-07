#!/bin/bash
set -u

# Portable Steam cutscene logger for the winevideo D3D9-to-DXMT bridge.
# Supply WINEVIDEO_CROSSOVER_APP, WINEVIDEO_BOTTLE, and
# WINEVIDEO_STEAM_APP_ID, or double-click the command and answer the prompts.

CX_APP="${WINEVIDEO_CROSSOVER_APP:-$HOME/Applications/CrossOver-winevideo.app}"
CX="$CX_APP/Contents/SharedSupport/CrossOver"
WINE="$CX/bin/wine"
BOTTLE="${WINEVIDEO_BOTTLE:-}"
APPID="${WINEVIDEO_STEAM_APP_ID:-}"

if [ -z "$BOTTLE" ]; then
  printf 'CrossOver bottle name: '
  read -r BOTTLE
fi
if [ -z "$APPID" ]; then
  printf 'Steam AppID: '
  read -r APPID
fi
if [ -z "$BOTTLE" ] || [ -z "$APPID" ]; then
  echo "ERROR: both a bottle and Steam AppID are required."
  exit 2
fi

BOTTLE_ROOT="$HOME/Library/Application Support/CrossOver/Bottles/$BOTTLE"
BOTTLE_CONF="$BOTTLE_ROOT/cxbottle.conf"
STAMP="$(date '+%Y%m%d-%H%M%S')"
LOG_ROOT="${WINEVIDEO_LOG_ROOT:-$HOME/Desktop/winevideo-bridge-logs}"
LOG_DIR="$LOG_ROOT/bridge-$STAMP"
WINE_LOG="$LOG_DIR/bridge.wine.log"
GST_LOG="$LOG_DIR/bridge.gstreamer.log"
RUNNER_LOG="$LOG_DIR/bridge.runner.log"
ENV_LOG="$LOG_DIR/bridge.env.txt"
SUMMARY="$LOG_DIR/bridge.summary.txt"

CX_DEBUGMSG="-all,-unwind,-process,-module,-threadname,+timestamp,+pid,+tid,+seh,+loaddll,+d3d9,+quartz,+winegstreamer,+strmbase,+devenum,+wmvcore"
GST_DEBUG="2,wine*:6,wg*:6,asfdemux:5,avdec*:5,videodecoder:5"

mkdir -p "$LOG_DIR"

log_msg() {
  printf '%s\n' "$*" | tee -a "$RUNNER_LOG"
}

pause_for_terminal() {
  printf '\nLog folder:\n  %s\n\nPress Return to close this window.' "$LOG_DIR"
  read -r _
}

count_pattern() {
  grep -cF -- "$1" "$WINE_LOG" 2>/dev/null || true
}

bridge_enabled="$(sed -n 's/^"WINE_D3D9_DXMT_VIDEO_BRIDGE"[[:space:]]*=[[:space:]]*"\([^"]*\)"/\1/p' "$BOTTLE_CONF" 2>/dev/null | tail -n 1)"
graphics_backend="$(sed -n 's/^"CX_GRAPHICS_BACKEND"[[:space:]]*=[[:space:]]*"\([^"]*\)"/\1/p' "$BOTTLE_CONF" 2>/dev/null | tail -n 1)"

{
  echo "date=$(date)"
  echo "cx_app=$CX_APP"
  echo "bottle=$BOTTLE"
  echo "appid=$APPID"
  echo "bridge_enabled=${bridge_enabled:-missing}"
  echo "graphics_backend=${graphics_backend:-missing}"
  echo "cx_debugmsg=$CX_DEBUGMSG"
  echo "gst_debug=$GST_DEBUG"
  if [ -f "$CX/lib/wine/x86_64-windows/d3d9.dll" ]; then
    echo "d3d9_sha256=$(shasum -a 256 "$CX/lib/wine/x86_64-windows/d3d9.dll" | awk '{print $1}')"
  else
    echo "d3d9_sha256=missing"
  fi
} > "$ENV_LOG"

if [ "${WINEVIDEO_LOG_DRY_RUN:-0}" = "1" ]; then
  echo "DRY RUN: Steam and the selected app were not launched."
  echo "bottle=$BOTTLE"
  echo "appid=$APPID"
  echo "log_dir=$LOG_DIR"
  exit 0
fi

if [ ! -x "$WINE" ]; then
  log_msg "ERROR: CrossOver wine wrapper is missing: $WINE"
  pause_for_terminal
  exit 1
fi

if [ "$bridge_enabled" != "1" ] || [ "$graphics_backend" != "dxmt" ]; then
  log_msg "ERROR: $BOTTLE is not configured for the installed bridge."
  log_msg "Expected WINE_D3D9_DXMT_VIDEO_BRIDGE=1 and CX_GRAPHICS_BACKEND=dxmt."
  pause_for_terminal
  exit 1
fi

log_msg "D3D9-to-DXMT video bridge logger"
log_msg "Logs: $LOG_DIR"
log_msg ""
log_msg "This will close Steam in $BOTTLE, then launch Steam appid $APPID under logging."
log_msg "After testing, quit both the game and Steam to finish the summary."
printf '\nPress Return to begin (Ctrl-C to abort)... '
read -r _

log_msg "Requesting a clean Steam/bottle session..."
CX_BOTTLE="$BOTTLE" "$WINE" --bottle "$BOTTLE" \
  --cx-app "C:\\Program Files (x86)\\Steam\\steam.exe" -shutdown \
  >> "$RUNNER_LOG" 2>&1 || true
sleep 3
CX_BOTTLE="$BOTTLE" "$WINE" --bottle "$BOTTLE" wineboot.exe -k \
  >> "$RUNNER_LOG" 2>&1 || true
sleep 2

export CX_BOTTLE
export CX_DEBUGMSG
export GST_DEBUG
export GST_DEBUG_FILE="$GST_LOG"
export WINE_D3D9_DXMT_VIDEO_BRIDGE=1
export CX_GRAPHICS_BACKEND=dxmt

log_msg "Launching Steam appid $APPID..."
"$WINE" \
  --bottle "$BOTTLE" \
  --cx-log "$WINE_LOG" \
  --debugmsg "$CX_DEBUGMSG" \
  --wait-children \
  --cx-app "C:\\Program Files (x86)\\Steam\\steam.exe" \
  -applaunch "$APPID" >> "$RUNNER_LOG" 2>&1
EXIT_CODE=$?

created="$(count_pattern 'd3d9-video-bridge: created')"
uploads="$(count_pattern 'd3d9-video-bridge: uploaded frame')"
destroyed="$(count_pattern 'd3d9-video-bridge: destroying sidecar')"
completion_failures="$(count_pattern 'd3d9-video-bridge: upload completion failed')"
upload_failures="$(count_pattern 'd3d9-video-bridge: upload failed')"
invalid_handles="$(count_pattern 'Invalid shared handle')"
dxgi_errors="$(count_pattern 'DXGI_ERROR')"
page_faults="$(count_pattern 'Unhandled page fault')"

{
  echo "D3D9-to-DXMT video bridge trace summary"
  echo "date=$(date)"
  echo "launch_exit_code=$EXIT_CODE"
  echo "sidecars_created=$created"
  echo "frame_uploads=$uploads"
  echo "sidecars_destroyed=$destroyed"
  echo "upload_completion_failures=$completion_failures"
  echo "upload_failures=$upload_failures"
  echo "invalid_shared_handles=$invalid_handles"
  echo "dxgi_errors=$dxgi_errors"
  echo "unhandled_page_faults=$page_faults"
  echo
  if [ "$created" -gt 0 ] && [ "$uploads" -gt 0 ] \
      && [ "$completion_failures" -eq 0 ] && [ "$upload_failures" -eq 0 ] \
      && [ "$invalid_handles" -eq 0 ] && [ "$dxgi_errors" -eq 0 ] \
      && [ "$page_faults" -eq 0 ]; then
    echo "verdict=CLEAN_BRIDGE_TRACE"
  else
    echo "verdict=REVIEW_TRACE"
  fi
  echo
  echo "Last bridge events:"
  grep -F 'd3d9-video-bridge:' "$WINE_LOG" 2>/dev/null | tail -n 20 || true
  echo
  echo "Matched warnings/errors:"
  grep -Ei 'd3d9-video-bridge:.*(failed|failure)|Invalid shared handle|DXGI_ERROR|device removed|Unhandled page fault|unhandled exception' \
    "$WINE_LOG" 2>/dev/null | tail -n 100 || true
} > "$SUMMARY"

log_msg ""
log_msg "Trace finished. Summary:"
tee -a "$RUNNER_LOG" < "$SUMMARY"

for file in "$WINE_LOG" "$GST_LOG"; do
  [ -f "$file" ] || continue
  gzip -f "$file"
done

log_msg ""
log_msg "Done. Logs saved to:"
log_msg "  $LOG_DIR"
pause_for_terminal
exit "$EXIT_CODE"
