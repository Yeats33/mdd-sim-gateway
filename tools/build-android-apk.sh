#!/bin/sh
set -eu

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
CLIENT_DIR="$REPO_DIR/clients/mdd_gateway_app"
DIST_DIR="$REPO_DIR/dist/android"

if [ -z "${MDD_ANDROID_PRIVATE_KEY:-}" ]; then
  echo "MDD_ANDROID_PRIVATE_KEY is required for an installable release APK" >&2
  exit 1
fi
if [ -z "${MDD_ANDROID_CERTIFICATE:-}" ]; then
  echo "MDD_ANDROID_CERTIFICATE is required for an installable release APK" >&2
  exit 1
fi
if [ -z "${MDD_ANDROID_KEY_PASSWORD_FILE:-}" ]; then
  echo "MDD_ANDROID_KEY_PASSWORD_FILE is required for an installable release APK" >&2
  exit 1
fi
for signing_file in \
  "$MDD_ANDROID_PRIVATE_KEY" \
  "$MDD_ANDROID_CERTIFICATE" \
  "$MDD_ANDROID_KEY_PASSWORD_FILE"; do
  if [ ! -f "$signing_file" ]; then
    echo "Android signing file not found: $signing_file" >&2
    exit 1
  fi
done

(cd "$CLIENT_DIR" && flutter pub get && flutter build apk --release \
  --target-platform android-arm64 --split-per-abi)

SOURCE_APK="$CLIENT_DIR/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
if [ ! -f "$SOURCE_APK" ]; then
  echo "expected arm64-v8a APK not found: $SOURCE_APK" >&2
  exit 1
fi

VERSION=$(sed -n 's/^version: \([^+]*\).*/\1/p' "$CLIENT_DIR/pubspec.yaml")
mkdir -p "$DIST_DIR"
OUTPUT_APK="$DIST_DIR/mdd-sim-gateway-${VERSION}-android-arm64-v8a.apk"

APKSIGNER=${MDD_APKSIGNER:-$(command -v apksigner || true)}
if [ -z "$APKSIGNER" ]; then
  for sdk in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" /opt/android-sdk; do
    if [ -n "$sdk" ] && [ -d "$sdk/build-tools" ]; then
      APKSIGNER=$(find "$sdk/build-tools" -mindepth 2 -maxdepth 2 -type f -name apksigner | sort -V | tail -1)
      [ -n "$APKSIGNER" ] && break
    fi
  done
fi
if [ -z "$APKSIGNER" ]; then
  echo "apksigner was not found; set MDD_APKSIGNER to the Android SDK tool" >&2
  exit 1
fi
if "$APKSIGNER" verify "$SOURCE_APK" >/dev/null 2>&1; then
  echo "release source APK was unexpectedly pre-signed" >&2
  exit 1
fi
"$APKSIGNER" sign \
  --key "$MDD_ANDROID_PRIVATE_KEY" \
  --cert "$MDD_ANDROID_CERTIFICATE" \
  --key-pass "file:$MDD_ANDROID_KEY_PASSWORD_FILE" \
  --v1-signing-enabled false \
  --v2-signing-enabled true \
  --v3-signing-enabled true \
  --v4-signing-enabled false \
  --debuggable-apk-permitted false \
  --out "$OUTPUT_APK" \
  "$SOURCE_APK"

ABIS=$(unzip -Z1 "$OUTPUT_APK" | sed -n 's#^lib/\([^/]*\)/.*#\1#p' | sort -u)
if [ "$ABIS" != "arm64-v8a" ]; then
  echo "unexpected APK ABI set: $ABIS" >&2
  exit 1
fi

"$APKSIGNER" verify --verbose --print-certs "$OUTPUT_APK"
echo "$OUTPUT_APK"
