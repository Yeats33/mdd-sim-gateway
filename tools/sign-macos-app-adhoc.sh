#!/bin/sh
set -eu

APP_DIR=${1:-}
ENTITLEMENTS=${2:-}

fail() {
  echo "macOS ad-hoc signing: $*" >&2
  exit 1
}

if [ "$(uname -s)" != Darwin ]; then
  fail "this script requires macOS"
fi
if [ -z "$APP_DIR" ] || [ ! -d "$APP_DIR" ]; then
  fail "app bundle not found: ${APP_DIR:-<missing>}"
fi
if [ -z "$ENTITLEMENTS" ] || [ ! -f "$ENTITLEMENTS" ]; then
  fail "entitlements file not found: ${ENTITLEMENTS:-<missing>}"
fi

is_mach_o() {
  /usr/bin/file -b "$1" 2>/dev/null | grep -q 'Mach-O'
}

sign_mach_o_files() {
  find "$APP_DIR/Contents" -type f -print | while IFS= read -r candidate; do
    if is_mach_o "$candidate"; then
      codesign --force --timestamp=none --sign - "$candidate"
    fi
  done
}

bundle_paths_deepest_first() {
  find "$APP_DIR/Contents" -type d \( \
    -name '*.framework' -o \
    -name '*.bundle' -o \
    -name '*.xpc' -o \
    -name '*.appex' -o \
    -name '*.app' \
  \) -print | \
    awk '{ path=$0; depth=gsub(/\//, "/", path); printf "%08d\t%s\n", depth, $0 }' | \
    sort -rn | cut -f2-
}

sign_nested_bundles() {
  bundle_paths_deepest_first | while IFS= read -r bundle; do
    [ -n "$bundle" ] || continue
    codesign --force --timestamp=none --sign - "$bundle"
  done
}

assert_adhoc() {
  code_path=$1
  details=$(codesign --display --verbose=4 "$code_path" 2>&1) || \
    fail "cannot inspect signature: $code_path"
  printf '%s\n' "$details" | grep -F 'Signature=adhoc' >/dev/null || \
    fail "code is not ad-hoc signed: $code_path"
  team_id=$(printf '%s\n' "$details" | sed -n 's/^TeamIdentifier=//p' | head -1)
  case "$team_id" in
    ''|'not set') ;;
    *) fail "third-party Team ID remains on $code_path: $team_id" ;;
  esac
}

audit_mach_o_files() {
  find "$APP_DIR/Contents" -type f -print | while IFS= read -r candidate; do
    if is_mach_o "$candidate"; then
      assert_adhoc "$candidate"
    fi
  done
}

audit_nested_bundles() {
  bundle_paths_deepest_first | while IFS= read -r bundle; do
    [ -n "$bundle" ] || continue
    assert_adhoc "$bundle"
  done
}

# Sign from the deepest executable code outward. Do not use --deep for signing:
# every bundled framework must have the same empty Team ID as the ad-hoc host.
sign_mach_o_files
sign_nested_bundles
codesign --force --options runtime --timestamp=none \
  --entitlements "$ENTITLEMENTS" --sign - "$APP_DIR"

codesign --verify --deep --strict --verbose=4 "$APP_DIR"
audit_mach_o_files
audit_nested_bundles
assert_adhoc "$APP_DIR"

echo "All macOS executable code is ad-hoc signed with no Team ID."
