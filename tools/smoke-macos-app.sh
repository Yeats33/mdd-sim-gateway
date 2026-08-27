#!/bin/sh
set -eu

APP_DIR=${1:-}
if [ "$(uname -s)" != Darwin ]; then
  echo "smoke-macos-app.sh requires macOS" >&2
  exit 1
fi
if [ -z "$APP_DIR" ] || [ ! -d "$APP_DIR" ]; then
  echo "app bundle not found: ${APP_DIR:-<missing>}" >&2
  exit 1
fi

EXECUTABLE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$APP_DIR/Contents/Info.plist")
APP_BINARY="$APP_DIR/Contents/MacOS/$EXECUTABLE"
if [ ! -x "$APP_BINARY" ]; then
  echo "app executable not found: $APP_BINARY" >&2
  exit 1
fi

LOG_FILE=${MDD_MACOS_SMOKE_LOG:-"${TMPDIR:-/tmp}/mdd-sim-gateway-smoke.log"}

# Launch through LaunchServices so the process is parented by launchd, matching
# a user opening the app from Finder. A direct binary launch does not exercise
# the same launch constraints on recent macOS versions.
/usr/bin/open -n -W "$APP_DIR" >"$LOG_FILE" 2>&1 &
LAUNCHER_PID=$!

cleanup() {
  for app_pid in $(pgrep -f "$APP_BINARY" 2>/dev/null || true); do
    kill -TERM "$app_pid" >/dev/null 2>&1 || true
  done
  if kill -0 "$LAUNCHER_PID" >/dev/null 2>&1; then
    kill -TERM "$LAUNCHER_PID" >/dev/null 2>&1 || true
  fi
  wait "$LAUNCHER_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM

elapsed=0
while [ "$elapsed" -lt 5 ]; do
  sleep 1
  elapsed=$((elapsed + 1))
  if ! kill -0 "$LAUNCHER_PID" >/dev/null 2>&1; then
    status=0
    wait "$LAUNCHER_PID" || status=$?
    echo "macOS app exited during the ${elapsed}s LaunchServices smoke test (status $status)" >&2
    sed -n '1,200p' "$LOG_FILE" >&2
    /usr/bin/log show --last 2m --style compact \
      --predicate 'process == "MDD Sim Gateway" OR eventMessage CONTAINS[c] "WebRTC.framework"' \
      2>/dev/null | tail -200 >&2 || true
    exit 1
  fi
done

echo "macOS app remained alive for the 5s LaunchServices/launchd smoke test."
