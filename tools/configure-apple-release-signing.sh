#!/bin/sh
set -eu

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
SIGNING_DIR=${MDD_APPLE_SIGNING_DIR:-"$REPO_DIR/../.signing/mdd-sim-gateway/apple"}
GITHUB_REPOSITORY=${MDD_GITHUB_REPOSITORY:-Yeats33/mdd-sim-gateway}
BUNDLE_ID=com.yeats33.mdd.gateway.ios

fail() {
  echo "Apple release signing: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

require_file() {
  [ -s "$1" ] || fail "required file is missing or empty: $1"
}

read_identifier() {
  tr -d '[:space:]' < "$1"
}

convert_certificate() {
  source_path=$1
  output_path=$2
  if openssl x509 -inform DER -in "$source_path" -out "$output_path" 2>/dev/null; then
    return
  fi
  openssl x509 -inform PEM -in "$source_path" -out "$output_path" 2>/dev/null || \
    fail "invalid X.509 certificate: $source_path"
}

verify_key_matches_certificate() {
  private_key=$1
  certificate=$2
  label=$3
  openssl pkey -in "$private_key" -pubout -outform DER -out "$TEMP_DIR/key-public.der" 2>/dev/null || \
    fail "invalid $label private key"
  openssl x509 -in "$certificate" -pubkey -noout 2>/dev/null | \
    openssl pkey -pubin -outform DER -out "$TEMP_DIR/certificate-public.der" 2>/dev/null || \
    fail "cannot extract the $label certificate public key"
  cmp -s "$TEMP_DIR/key-public.der" "$TEMP_DIR/certificate-public.der" || \
    fail "$label certificate does not match the locally generated private key"
}

require_command cmp
require_command gh
require_command grep
require_command openssl
require_command python3

IOS_CERTIFICATE_CER="$SIGNING_DIR/apple-distribution.cer"
IOS_PRIVATE_KEY="$SIGNING_DIR/apple-distribution-private-key.pem"
IOS_P12_PASSWORD="$SIGNING_DIR/apple-distribution-p12-password"
IOS_PROFILE="$SIGNING_DIR/mdd-sim-gateway.mobileprovision"
MAC_CERTIFICATE_CER="$SIGNING_DIR/developer-id-application.cer"
MAC_PRIVATE_KEY="$SIGNING_DIR/developer-id-application-private-key.pem"
MAC_P12_PASSWORD="$SIGNING_DIR/developer-id-p12-password"
NOTARY_KEY="$SIGNING_DIR/notary-team-key.p8"
TEAM_ID_FILE="$SIGNING_DIR/apple-team-id"
NOTARY_KEY_ID_FILE="$SIGNING_DIR/notary-key-id"
NOTARY_ISSUER_ID_FILE="$SIGNING_DIR/notary-issuer-id"
KEYCHAIN_PASSWORD_FILE="$SIGNING_DIR/github-actions-keychain-password"

for required in \
  "$IOS_CERTIFICATE_CER" \
  "$IOS_PRIVATE_KEY" \
  "$IOS_P12_PASSWORD" \
  "$IOS_PROFILE" \
  "$MAC_CERTIFICATE_CER" \
  "$MAC_PRIVATE_KEY" \
  "$MAC_P12_PASSWORD" \
  "$NOTARY_KEY" \
  "$TEAM_ID_FILE" \
  "$NOTARY_KEY_ID_FILE" \
  "$NOTARY_ISSUER_ID_FILE" \
  "$KEYCHAIN_PASSWORD_FILE"; do
  require_file "$required"
done
chmod 0600 \
  "$IOS_CERTIFICATE_CER" \
  "$IOS_PRIVATE_KEY" \
  "$IOS_P12_PASSWORD" \
  "$IOS_PROFILE" \
  "$MAC_CERTIFICATE_CER" \
  "$MAC_PRIVATE_KEY" \
  "$MAC_P12_PASSWORD" \
  "$NOTARY_KEY" \
  "$TEAM_ID_FILE" \
  "$NOTARY_KEY_ID_FILE" \
  "$NOTARY_ISSUER_ID_FILE" \
  "$KEYCHAIN_PASSWORD_FILE"

TEAM_ID=$(read_identifier "$TEAM_ID_FILE")
NOTARY_KEY_ID=$(read_identifier "$NOTARY_KEY_ID_FILE")
NOTARY_ISSUER_ID=$(read_identifier "$NOTARY_ISSUER_ID_FILE")
case "$TEAM_ID" in
  *[!A-Z0-9]*|'') fail "apple-team-id must contain only uppercase letters and digits" ;;
esac
[ "${#TEAM_ID}" -eq 10 ] || fail "apple-team-id must be exactly 10 characters"
case "$NOTARY_KEY_ID" in
  *[!A-Z0-9]*|'') fail "notary-key-id must contain only uppercase letters and digits" ;;
esac
[ "${#NOTARY_KEY_ID}" -eq 10 ] || fail "notary-key-id must be exactly 10 characters"
case "$NOTARY_ISSUER_ID" in
  *[!0-9A-Fa-f-]*|'') fail "notary-issuer-id is not a UUID" ;;
esac
[ "${#NOTARY_ISSUER_ID}" -eq 36 ] || fail "notary-issuer-id must be a 36-character UUID"

TEMP_DIR=$(mktemp -d)
trap 'rm -r "$TEMP_DIR"' EXIT HUP INT TERM
chmod 0700 "$TEMP_DIR"

IOS_CERTIFICATE_PEM="$TEMP_DIR/apple-distribution.pem"
MAC_CERTIFICATE_PEM="$TEMP_DIR/developer-id-application.pem"
PROFILE_PLIST="$TEMP_DIR/profile.plist"
IOS_P12="$SIGNING_DIR/apple-distribution.p12"
MAC_P12="$SIGNING_DIR/developer-id-application.p12"

convert_certificate "$IOS_CERTIFICATE_CER" "$IOS_CERTIFICATE_PEM"
convert_certificate "$MAC_CERTIFICATE_CER" "$MAC_CERTIFICATE_PEM"
openssl x509 -in "$IOS_CERTIFICATE_PEM" -noout -subject | \
  grep -F 'Apple Distribution:' >/dev/null || fail "apple-distribution.cer is not an Apple Distribution certificate"
openssl x509 -in "$MAC_CERTIFICATE_PEM" -noout -subject | \
  grep -F 'Developer ID Application:' >/dev/null || fail "developer-id-application.cer is not a Developer ID Application certificate"
openssl x509 -in "$IOS_CERTIFICATE_PEM" -noout -subject -nameopt RFC2253 | \
  grep -F "OU=$TEAM_ID" >/dev/null || fail "Apple Distribution certificate has the wrong Team ID"
openssl x509 -in "$MAC_CERTIFICATE_PEM" -noout -subject -nameopt RFC2253 | \
  grep -F "OU=$TEAM_ID" >/dev/null || fail "Developer ID Application certificate has the wrong Team ID"
openssl x509 -in "$IOS_CERTIFICATE_PEM" -checkend 86400 -noout >/dev/null || \
  fail "Apple Distribution certificate is expired or expires within 24 hours"
openssl x509 -in "$MAC_CERTIFICATE_PEM" -checkend 86400 -noout >/dev/null || \
  fail "Developer ID Application certificate is expired or expires within 24 hours"
verify_key_matches_certificate "$IOS_PRIVATE_KEY" "$IOS_CERTIFICATE_PEM" "Apple Distribution"
verify_key_matches_certificate "$MAC_PRIVATE_KEY" "$MAC_CERTIFICATE_PEM" "Developer ID Application"

openssl smime -verify -inform DER -in "$IOS_PROFILE" -noverify -out "$PROFILE_PLIST" 2>/dev/null || \
  fail "invalid provisioning profile CMS envelope"
python3 - "$PROFILE_PLIST" "$IOS_CERTIFICATE_PEM" "$TEAM_ID" "$BUNDLE_ID" <<'PY'
from datetime import datetime, timezone
from hashlib import sha256
from pathlib import Path
import plistlib
import ssl
import sys

profile_path, certificate_path, team_id, bundle_id = sys.argv[1:]
with open(profile_path, "rb") as handle:
    profile = plistlib.load(handle)

expires = profile.get("ExpirationDate")
if not isinstance(expires, datetime):
    raise SystemExit("provisioning profile has no expiration date")
if expires.tzinfo is None:
    expires = expires.replace(tzinfo=timezone.utc)
if expires <= datetime.now(timezone.utc):
    raise SystemExit("provisioning profile is expired")

if team_id not in profile.get("TeamIdentifier", []):
    raise SystemExit("provisioning profile has the wrong Apple Team ID")
entitlements = profile.get("Entitlements", {})
if entitlements.get("application-identifier") != f"{team_id}.{bundle_id}":
    raise SystemExit("provisioning profile has the wrong application identifier")
if entitlements.get("get-task-allow") is not False:
    raise SystemExit("provisioning profile is not a distribution profile")
if not profile.get("ProvisionedDevices"):
    raise SystemExit("provisioning profile contains no registered Ad Hoc devices")

certificate_pem = Path(certificate_path).read_text()
certificate_der = ssl.PEM_cert_to_DER_cert(certificate_pem)
expected_digest = sha256(certificate_der).digest()
profile_digests = {sha256(item).digest() for item in profile.get("DeveloperCertificates", [])}
if expected_digest not in profile_digests:
    raise SystemExit("provisioning profile does not contain the supplied Apple Distribution certificate")
PY

openssl pkey -in "$NOTARY_KEY" -noout -check >/dev/null 2>&1 || \
  fail "notary-team-key.p8 is not a valid private key"

openssl pkcs12 -export -inkey "$IOS_PRIVATE_KEY" -in "$IOS_CERTIFICATE_PEM" \
  -out "$IOS_P12" -passout file:"$IOS_P12_PASSWORD" \
  -keypbe AES-256-CBC -certpbe AES-256-CBC -macalg sha256
openssl pkcs12 -export -inkey "$MAC_PRIVATE_KEY" -in "$MAC_CERTIFICATE_PEM" \
  -out "$MAC_P12" -passout file:"$MAC_P12_PASSWORD" \
  -keypbe AES-256-CBC -certpbe AES-256-CBC -macalg sha256
chmod 0600 "$IOS_P12" "$MAC_P12"

openssl base64 -A -in "$IOS_P12" | \
  gh secret set APPLE_IOS_DISTRIBUTION_P12_BASE64 --repo "$GITHUB_REPOSITORY"
gh secret set APPLE_IOS_DISTRIBUTION_P12_PASSWORD --repo "$GITHUB_REPOSITORY" < "$IOS_P12_PASSWORD"
openssl base64 -A -in "$IOS_PROFILE" | \
  gh secret set APPLE_IOS_PROVISIONING_PROFILE_BASE64 --repo "$GITHUB_REPOSITORY"
openssl base64 -A -in "$MAC_P12" | \
  gh secret set APPLE_DEVELOPER_ID_P12_BASE64 --repo "$GITHUB_REPOSITORY"
gh secret set APPLE_DEVELOPER_ID_P12_PASSWORD --repo "$GITHUB_REPOSITORY" < "$MAC_P12_PASSWORD"
gh secret set APPLE_KEYCHAIN_PASSWORD --repo "$GITHUB_REPOSITORY" < "$KEYCHAIN_PASSWORD_FILE"
openssl base64 -A -in "$NOTARY_KEY" | \
  gh secret set APPLE_NOTARY_KEY_BASE64 --repo "$GITHUB_REPOSITORY"
printf '%s' "$TEAM_ID" | gh secret set APPLE_TEAM_ID --repo "$GITHUB_REPOSITORY"
printf '%s' "$NOTARY_KEY_ID" | gh secret set APPLE_NOTARY_KEY_ID --repo "$GITHUB_REPOSITORY"
printf '%s' "$NOTARY_ISSUER_ID" | gh secret set APPLE_NOTARY_ISSUER_ID --repo "$GITHUB_REPOSITORY"
gh variable set IOS_EXPORT_METHOD --body release-testing --repo "$GITHUB_REPOSITORY"

echo "Apple signing material validated and GitHub release secrets configured."
