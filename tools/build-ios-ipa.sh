#!/bin/sh
set -eu

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
CLIENT_DIR="$REPO_DIR/clients/mdd_gateway_app"
DIST_DIR="$REPO_DIR/dist/ios"

if [ "$(uname -s)" != Darwin ]; then
  echo "build-ios-ipa.sh requires macOS with Xcode" >&2
  exit 1
fi

(cd "$CLIENT_DIR" && flutter pub get && flutter build ios --release --no-codesign)

APP_DIR="$CLIENT_DIR/build/ios/iphoneos/Runner.app"
if [ ! -d "$APP_DIR" ]; then
  echo "expected unsigned iOS app bundle not found: $APP_DIR" >&2
  exit 1
fi
if codesign --verify "$APP_DIR" >/dev/null 2>&1; then
  echo "iOS app was unexpectedly signed" >&2
  exit 1
fi
if [ -d "$APP_DIR/_CodeSignature" ] || [ -f "$APP_DIR/embedded.mobileprovision" ]; then
  echo "iOS app unexpectedly contains signing material" >&2
  exit 1
fi

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP_DIR/Info.plist")
if [ "$BUNDLE_ID" != "com.yeats33.mdd.gateway.ios" ]; then
  echo "unexpected iOS bundle identifier: $BUNDLE_ID" >&2
  exit 1
fi

VERSION=$(sed -n 's/^version: \([^+]*\).*/\1/p' "$CLIENT_DIR/pubspec.yaml")
STAGING_DIR=$(mktemp -d "$CLIENT_DIR/build/ios/unsigned-ipa.XXXXXX")
trap 'rm -r "$STAGING_DIR"' EXIT HUP INT TERM
mkdir -p "$STAGING_DIR/Payload" "$DIST_DIR"
ditto "$APP_DIR" "$STAGING_DIR/Payload/Runner.app"

# Prebuilt Flutter plugin frameworks can retain vendor/ad-hoc signatures even
# when Xcode builds the top-level app with CODE_SIGNING_ALLOWED=NO. Strip every
# executable signature from the disposable Payload copy so the IPA has one
# unambiguous state and can be re-signed by the recipient.
find "$STAGING_DIR/Payload" -type f -perm -111 \
  -exec codesign --remove-signature {} \; 2>/dev/null || true
find "$STAGING_DIR/Payload" -type d -name _CodeSignature -prune \
  -exec rm -r {} \;
find "$STAGING_DIR/Payload" -type f -name embedded.mobileprovision -delete

if find "$STAGING_DIR/Payload" -type f -perm -111 \
  -exec sh -c 'for candidate in "$@"; do codesign --verify "$candidate" >/dev/null 2>&1 && exit 0; done; exit 1' sh {} +; then
  echo "unsigned IPA payload still contains signed executable code" >&2
  exit 1
fi

OUTPUT_IPA="$DIST_DIR/mdd-sim-gateway-${VERSION}-ios-unsigned.ipa"
(cd "$STAGING_DIR" && ditto -c -k --sequesterRsrc --keepParent Payload "$OUTPUT_IPA")

unzip -tq "$OUTPUT_IPA" >/dev/null
unzip -Z1 "$OUTPUT_IPA" | grep -Fqx 'Payload/Runner.app/Info.plist'
if unzip -Z1 "$OUTPUT_IPA" | grep -Eq '(^|/)(_CodeSignature|embedded\.mobileprovision)(/|$)'; then
  echo "unsigned IPA archive unexpectedly contains signing material" >&2
  exit 1
fi

echo "$OUTPUT_IPA"
