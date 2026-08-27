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

SMOKE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/mdd-lima-vz-smoke.XXXXXX")
LIMA_HOME_DIR="$SMOKE_ROOT/lima-home"
VM_NAME="mdd-vz-runtime-smoke"
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

if ! LIMA_HOME="$LIMA_HOME_DIR" "$LIMACTL" create \
  --name "$VM_NAME" "$TEMPLATE"; then
  dump_vm_logs
  exit 1
fi
if ! LIMA_HOME="$LIMA_HOME_DIR" "$LIMACTL" start "$VM_NAME"; then
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
