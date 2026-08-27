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

LIMA_GUEST_AGENT=${MDD_LIMA_GUEST_AGENT:-}
if [ -z "$LIMA_GUEST_AGENT" ]; then
  LIMA_PREFIX=$(CDPATH= cd -- "$(dirname -- "$LIMACTL_BIN")/.." && pwd -P)
  for candidate in \
    "$LIMA_PREFIX/share/lima/lima-guestagent.Linux-aarch64.gz" \
    "$LIMA_PREFIX/share/lima/lima-guestagent.Linux-aarch64"; do
    if [ -f "$candidate" ]; then
      LIMA_GUEST_AGENT=$candidate
      break
    fi
  done
fi
if [ -z "$LIMA_GUEST_AGENT" ] && command -v brew >/dev/null 2>&1; then
  BREW_LIMA_PREFIX=$(brew --prefix lima 2>/dev/null || true)
  for candidate in \
    "$BREW_LIMA_PREFIX/share/lima/lima-guestagent.Linux-aarch64.gz" \
    "$BREW_LIMA_PREFIX/share/lima/lima-guestagent.Linux-aarch64"; do
    if [ -n "$BREW_LIMA_PREFIX" ] && [ -f "$candidate" ]; then
      LIMA_GUEST_AGENT=$candidate
      break
    fi
  done
fi
if [ -z "$LIMA_GUEST_AGENT" ] || [ ! -f "$LIMA_GUEST_AGENT" ]; then
  echo "Linux-aarch64 Lima guest agent is required; set MDD_LIMA_GUEST_AGENT" >&2
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
LIMA_BUNDLE="$RESOURCES/lima"
BUNDLED_LIMACTL="$LIMA_BUNDLE/bin/limactl"
BUNDLED_LIMA_SHARE="$LIMA_BUNDLE/share/lima"
COMPAT_LIMA_SHARE="$APP_DIR/Contents/share"
mkdir -p \
  "$RESOURCES" \
  "$SOURCE" \
  "$LIMA_BUNDLE/bin" \
  "$BUNDLED_LIMA_SHARE" \
  "$COMPAT_LIMA_SHARE"
install -m 0755 "$HOSTD_DIR/target/aarch64-apple-darwin/release/mdd-hostd" "$RESOURCES/mdd-hostd"
install -m 0755 "$LIMACTL_BIN" "$BUNDLED_LIMACTL"
install -m 0644 "$LIMA_GUEST_AGENT" "$BUNDLED_LIMA_SHARE/$(basename -- "$LIMA_GUEST_AGENT")"
ln -sfn "lima/bin/limactl" "$RESOURCES/limactl"
ln -sfn "../Resources/lima/share/lima" "$COMPAT_LIMA_SHARE/lima"
# Expand while the source installation still has its complete template catalog.
# The relocated bundle intentionally carries only runtime files needed by the App.
"$LIMACTL_BIN" template copy --embed-all "$HOSTD_DIR/templates/mdd-vm.yaml" > "$RESOURCES/mdd-vm.yaml"
if ! grep -Fq '__MDD_SOURCE__' "$RESOURCES/mdd-vm.yaml"; then
  echo "expanded Lima template lost the runtime source mount placeholder" >&2
  exit 1
fi
if grep -Eq '__MDD_BASE__|template:(//)?ubuntu-24\.04' "$RESOURCES/mdd-vm.yaml"; then
  echo "expanded Lima template still contains a runtime base-template dependency" >&2
  exit 1
fi
chmod 0644 "$RESOURCES/mdd-vm.yaml"

for item in control engine host patches tools webui install.sh update-policy.json VERSION; do
  if [ -d "$REPO_DIR/$item" ]; then
    rsync -a --delete --exclude node_modules --exclude dist "$REPO_DIR/$item/" "$SOURCE/$item/"
  else
    install -m 0644 "$REPO_DIR/$item" "$SOURCE/$item"
  fi
done
chmod 0755 "$SOURCE/install.sh"

echo "$APP_DIR"
