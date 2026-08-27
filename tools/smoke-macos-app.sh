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
"$APP_BINARY" >"$LOG_FILE" 2>&1 &
APP_PID=$!

cleanup() {
  if kill -0 "$APP_PID" >/dev/null 2>&1; then
    kill -TERM "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT HUP INT TERM

elapsed=0
while [ "$elapsed" -lt 5 ]; do
  sleep 1
  elapsed=$((elapsed + 1))
  if ! kill -0 "$APP_PID" >/dev/null 2>&1; then
    status=0
    wait "$APP_PID" || status=$?
    echo "macOS app exited during the ${elapsed}s launch smoke test (status $status)" >&2
    sed -n '1,200p' "$LOG_FILE" >&2
    exit 1
  fi
done

echo "macOS app remained alive for the 5s launch smoke test."
