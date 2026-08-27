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
NATIVE_BUILD="$SOURCE/.mdd-native-build"
TEMPLATE="$RESOURCES/mdd-vm.yaml"
LIMACTL="$RESOURCES/lima/bin/limactl"
LIMA_SHARE="$RESOURCES/lima/share/lima"
GUEST_AGENT="$LIMA_SHARE/lima-guestagent.Linux-aarch64.gz"
if [ ! -f "$GUEST_AGENT" ]; then
  GUEST_AGENT="$LIMA_SHARE/lima-guestagent.Linux-aarch64"
fi
COMPAT_LIMACTL="$RESOURCES/limactl"
COMPAT_GUEST_AGENT="$APP_DIR/Contents/share/lima/$(basename -- "$GUEST_AGENT")"
for required in \
  "$HOSTD" \
  "$SOURCE" \
  "$NATIVE_BUILD" \
  "$TEMPLATE" \
  "$LIMACTL" \
  "$GUEST_AGENT" \
  "$COMPAT_LIMACTL" \
  "$COMPAT_GUEST_AGENT"; do
  [ -e "$required" ] || {
    echo "bundled host resource missing: $required" >&2
    exit 1
  }
done

if [ -n "${APP_VERSION:-}" ] && [ "$(sed -n '1p' "$NATIVE_BUILD")" != "$APP_VERSION" ]; then
  echo "bundled gateway source native version does not match $APP_VERSION" >&2
  exit 1
fi
echo "Bundled gateway source carries the native App version marker."

if ! otool -L "$HOSTD" | grep -Fq '/System/Library/Frameworks/PCSC.framework/'; then
  echo "bundled mdd-hostd is not linked to the macOS PCSC framework" >&2
  exit 1
fi
if ! grep -Fq 'hostPort: 32512' "$TEMPLATE" || ! grep -Fq 'hostIP: 127.0.0.1' "$TEMPLATE"; then
  echo "bundled VM template is missing the loopback-only Mac PC/SC bridge forward" >&2
  exit 1
fi
echo "Bundled mdd-hostd and VM template include the loopback-only Mac PC/SC bridge."

case "$GUEST_AGENT" in
  *.gz)
    gzip -t "$GUEST_AGENT"
    GUEST_AGENT_MAGIC=$(python3 - "$GUEST_AGENT" <<'PY'
import gzip
import sys

with gzip.open(sys.argv[1], "rb") as stream:
    print(stream.read(4).hex())
PY
)
    ;;
  *)
    GUEST_AGENT_MAGIC=$(od -An -tx1 -N4 "$GUEST_AGENT" | tr -d ' \n')
    ;;
esac
if [ "$GUEST_AGENT_MAGIC" != 7f454c46 ]; then
  echo "bundled Linux-aarch64 Lima guest agent is not an ELF binary" >&2
  exit 1
fi
echo "Bundled Lima Linux-aarch64 guest agent passed layout and ELF validation."
"$COMPAT_LIMACTL" --version
echo "Legacy bundled limactl path remains executable with a matching guest-agent layout."

STATE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/mdd-hostd-smoke.XXXXXX")
LOG_FILE="$STATE_DIR/hostd.log"
if ! "$HOSTD" \
  --state-dir "$STATE_DIR/validate-state" \
  --source-dir "$SOURCE" \
  --lima-template "$TEMPLATE" \
  --lima-bin "$LIMACTL" \
  --validate-template-only \
  >"$STATE_DIR/template-validation.log" 2>&1; then
  echo "bundled Lima VM template validation failed" >&2
  sed -n '1,200p' "$STATE_DIR/template-validation.log" >&2
  rm -r "$STATE_DIR"
  exit 1
fi
echo "Bundled single-file Lima VM template passed validation."

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
    [ "$response" = '{"ok":true,"service":"mdd-hostd","protocol":5}' ] || {
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
