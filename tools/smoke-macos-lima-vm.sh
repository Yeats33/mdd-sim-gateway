#!/bin/sh
set -eu

APP_DIR=${1:-}
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
  echo "smoke-macos-lima-vm.sh requires an Apple Silicon Mac" >&2
  exit 1
fi
if [ -z "$APP_DIR" ] || [ ! -d "$APP_DIR" ]; then
  echo "app bundle not found: ${APP_DIR:-<missing>}" >&2
  exit 1
fi

RESOURCES="$APP_DIR/Contents/Resources"
TEMPLATE="$RESOURCES/mdd-vz-smoke.yaml"
LIMACTL="$RESOURCES/lima/bin/limactl"
for required in "$TEMPLATE" "$LIMACTL"; do
  [ -e "$required" ] || {
    echo "bundled VM smoke resource missing: $required" >&2
    exit 1
  }
done

SMOKE_ROOT=$(mktemp -d /tmp/mvz.XXXXXX)
SMOKE_ROOT=$(CDPATH= cd -- "$SMOKE_ROOT" && pwd -P)
LIMA_HOME_DIR="$SMOKE_ROOT/l"
VM_NAME="vz"
mkdir -p "$LIMA_HOME_DIR"

dump_vm_logs() {
  for log_file in \
    "$LIMA_HOME_DIR/$VM_NAME/ha.stderr.log" \
    "$LIMA_HOME_DIR/$VM_NAME"/serial*.log; do
    if [ -f "$log_file" ]; then
      echo "--- $log_file" >&2
      sed -n '1,240p' "$log_file" >&2
    fi
  done
}

cleanup() {
  LIMA_HOME="$LIMA_HOME_DIR" "$LIMACTL" stop "$VM_NAME" >/dev/null 2>&1 || true
  LIMA_HOME="$LIMA_HOME_DIR" "$LIMACTL" delete --force "$VM_NAME" >/dev/null 2>&1 || true
  rm -r "$SMOKE_ROOT"
}
trap cleanup EXIT HUP INT TERM

# Lima appends a randomized suffix to ssh.sock. Keep the fully resolved path
# below macOS UNIX_PATH_MAX before doing any image or VM work.
SOCKET_PROBE="$LIMA_HOME_DIR/$VM_NAME/ssh.sock.1234567890123456"
if [ "${#SOCKET_PROBE}" -ge 104 ]; then
  echo "VZ smoke socket path is too long (${#SOCKET_PROBE} bytes): $SOCKET_PROBE" >&2
  exit 1
fi

if ! LIMA_HOME="$LIMA_HOME_DIR" "$LIMACTL" create \
  --name "$VM_NAME" "$TEMPLATE"; then
  dump_vm_logs
  exit 1
fi
if ! LIMA_HOME="$LIMA_HOME_DIR" "$LIMACTL" start "$VM_NAME"; then
  HARDWARE_LOG="$LIMA_HOME_DIR/$VM_NAME/ha.stderr.log"
  if [ "${MDD_ALLOW_NO_VIRTUALIZATION:-0}" = 1 ] && \
    [ -f "$HARDWARE_LOG" ] && \
    grep -Fq 'Virtualization is not available on this hardware.' "$HARDWARE_LOG"; then
    echo "VZ runtime boot explicitly skipped: this host does not expose virtualization hardware."
    echo "Bundled limactl entitlements and VZ initialization passed before the hardware gate."
    exit 0
  fi
  dump_vm_logs
  exit 1
fi

GUEST_ARCH=$(LIMA_HOME="$LIMA_HOME_DIR" "$LIMACTL" shell "$VM_NAME" -- uname -m | tr -d '\r\n')
if [ "$GUEST_ARCH" != aarch64 ]; then
  echo "unexpected Lima VM guest architecture: $GUEST_ARCH" >&2
  dump_vm_logs
  exit 1
fi

echo "Bundled signed limactl started a real VZ Linux-aarch64 VM successfully."
