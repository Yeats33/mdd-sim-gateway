#!/bin/sh
set -eu

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
CLIENT_DIR="$REPO_DIR/clients/mdd_gateway_app"
HOSTD_DIR="$REPO_DIR/native/mdd-hostd"

if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
  echo "build-macos-app.sh requires an Apple Silicon Mac" >&2
  exit 1
fi

LIMACTL_BIN=${MDD_LIMA_BIN:-}
if [ -z "$LIMACTL_BIN" ]; then
  LIMACTL_BIN=$(command -v limactl || true)
fi
if [ -z "$LIMACTL_BIN" ] || [ ! -x "$LIMACTL_BIN" ]; then
  echo "limactl is required; set MDD_LIMA_BIN to the reviewed Apple Silicon binary" >&2
  exit 1
fi

(cd "$HOSTD_DIR" && cargo build --release --target aarch64-apple-darwin)
(cd "$CLIENT_DIR" && flutter pub get && flutter build macos --release)

APP_DIR="$CLIENT_DIR/build/macos/Build/Products/Release/MDD Sim Gateway.app"
if [ ! -d "$APP_DIR" ]; then
  echo "expected app bundle not found: $APP_DIR" >&2
  exit 1
fi

RESOURCES="$APP_DIR/Contents/Resources"
SOURCE="$RESOURCES/gateway-source"
mkdir -p "$RESOURCES" "$SOURCE"
install -m 0755 "$HOSTD_DIR/target/aarch64-apple-darwin/release/mdd-hostd" "$RESOURCES/mdd-hostd"
install -m 0755 "$LIMACTL_BIN" "$RESOURCES/limactl"
install -m 0644 "$HOSTD_DIR/templates/mdd-vm.yaml" "$RESOURCES/mdd-vm.yaml"

for item in control engine host patches tools webui install.sh update-policy.json VERSION; do
  if [ -d "$REPO_DIR/$item" ]; then
    rsync -a --delete --exclude node_modules --exclude dist "$REPO_DIR/$item/" "$SOURCE/$item/"
  else
    install -m 0644 "$REPO_DIR/$item" "$SOURCE/$item"
  fi
done
chmod 0755 "$SOURCE/install.sh"

echo "$APP_DIR"
