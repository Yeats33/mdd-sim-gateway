#!/bin/sh
set -eu

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
CLIENT_DIR="$REPO_DIR/clients/mdd_gateway_app"

if [ "$(uname -s)" != Darwin ]; then
  echo "build-ios-ipa.sh requires macOS with Xcode" >&2
  exit 1
fi

if [ -z "${MDD_IOS_EXPORT_OPTIONS_PLIST:-}" ]; then
  echo "Set MDD_IOS_EXPORT_OPTIONS_PLIST to an Xcode export options plist." >&2
  echo "An installable IPA requires the owner's Apple Developer signing identity and profile." >&2
  exit 1
fi
if [ ! -f "$MDD_IOS_EXPORT_OPTIONS_PLIST" ]; then
  echo "export options file not found: $MDD_IOS_EXPORT_OPTIONS_PLIST" >&2
  exit 1
fi

(cd "$CLIENT_DIR" && flutter pub get && flutter build ipa --release \
  --export-options-plist="$MDD_IOS_EXPORT_OPTIONS_PLIST")

find "$CLIENT_DIR/build/ios/ipa" -maxdepth 1 -type f -name '*.ipa' -print
