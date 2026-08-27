#!/bin/sh
set -eu

APP_DIR=${1:-}
if [ "$(uname -s)" != Darwin ]; then
  echo "smoke-macos-hostd.sh requires macOS" >&2
  exit 1
fi
if [ -z "$APP_DIR" ] || [ ! -d "$APP_DIR" ]; then
  echo "app bundle not found: ${APP_DIR:-<missing>}" >&2
  exit 1
fi

RESOURCES="$APP_DIR/Contents/Resources"
HOSTD="$RESOURCES/mdd-hostd"
SOURCE="$RESOURCES/gateway-source"
TEMPLATE="$RESOURCES/mdd-vm.yaml"
LIMACTL="$RESOURCES/limactl"
for required in "$HOSTD" "$SOURCE" "$TEMPLATE" "$LIMACTL"; do
  [ -e "$required" ] || {
    echo "bundled host resource missing: $required" >&2
    exit 1
  }
done

STATE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/mdd-hostd-smoke.XXXXXX")
LOG_FILE="$STATE_DIR/hostd.log"
"$HOSTD" \
  --bind 127.0.0.1:48631 \
  --state-dir "$STATE_DIR/state" \
  --source-dir "$SOURCE" \
  --lima-template "$TEMPLATE" \
  --lima-bin "$LIMACTL" \
  >"$LOG_FILE" 2>&1 &
HOSTD_PID=$!

cleanup() {
  if kill -0 "$HOSTD_PID" >/dev/null 2>&1; then
    kill -TERM "$HOSTD_PID" >/dev/null 2>&1 || true
  fi
  wait "$HOSTD_PID" >/dev/null 2>&1 || true
  rm -r "$STATE_DIR"
}
trap cleanup EXIT HUP INT TERM

attempt=0
while [ "$attempt" -lt 20 ]; do
  if ! kill -0 "$HOSTD_PID" >/dev/null 2>&1; then
    status=0
    wait "$HOSTD_PID" || status=$?
    echo "bundled mdd-hostd exited before health check (status $status)" >&2
    sed -n '1,200p' "$LOG_FILE" >&2
    exit 1
  fi
  if response=$(/usr/bin/curl --fail --silent --show-error --max-time 1 \
    http://127.0.0.1:48631/v1/health 2>/dev/null); then
    [ "$response" = '{"ok":true,"service":"mdd-hostd"}' ] || {
      echo "unexpected mdd-hostd health response: $response" >&2
      exit 1
    }
    echo "Bundled mdd-hostd accepted --lima-bin and passed /v1/health."
    exit 0
  fi
  sleep 0.25
  attempt=$((attempt + 1))
done

echo "bundled mdd-hostd health check timed out" >&2
sed -n '1,200p' "$LOG_FILE" >&2
exit 1
