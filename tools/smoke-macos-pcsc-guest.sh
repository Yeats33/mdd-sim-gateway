#!/bin/sh
set -eu

REPO_DIR=${1:-/repo}
if [ ! -f "$REPO_DIR/install.sh" ]; then
  echo "repository install.sh not found: $REPO_DIR" >&2
  exit 1
fi

export MDD_DATA_DIR=/var/lib/mdd-sim-gateway
export MDD_MACOS_PCSC_BRIDGE=1
export MDD_MACOS_PCSC_BASE_PORT=32512
sh "$REPO_DIR/install.sh" macos-pcsc

CONFIG=/etc/reader.conf.d/mdd-macos-pcsc
test -f "$CONFIG"
grep -Fqx 'FRIENDLYNAME "Mac USB Smart Card Bridge"' "$CONFIG"
grep -Fqx 'DEVICENAME /dev/null:0x7F00' "$CONFIG"
grep -Fqx 'CHANNELID 0x7F00' "$CONFIG"
BRIDGE_LIB=$(sed -n 's/^LIBPATH //p' "$CONFIG")
test -n "$BRIDGE_LIB"
test -f "$BRIDGE_LIB"
test -f "$(dirname -- "$BRIDGE_LIB")/.mdd-vpcd-0.8-slots-1"
ldd "$BRIDGE_LIB"
if ldd "$BRIDGE_LIB" | grep -Fq 'not found'; then
  echo "Mac PC/SC virtual reader has an unresolved shared library" >&2
  exit 1
fi

echo "Linux guest built and registered the isolated one-slot Mac PC/SC reader."
