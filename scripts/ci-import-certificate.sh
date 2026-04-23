#!/usr/bin/env bash
# ci-import-certificate.sh
# Imports a Developer ID or Mac App Distribution certificate into a temporary keychain
# for use in CI environments (GitHub Actions / XCRunner).
#
# Required environment variables:
#   CERTIFICATE_P12_BASE64  — base64-encoded .p12 certificate file
#   CERTIFICATE_PASSWORD    — passphrase for the .p12 file
#
# Optional environment variables:
#   KEYCHAIN_NAME           — name for the temporary keychain (default: ci-build.keychain)

set -euo pipefail

KEYCHAIN_NAME="${KEYCHAIN_NAME:-ci-build.keychain}"
# Generate a random password — never use a hardcoded default
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"
CERTIFICATE_PATH="${RUNNER_TEMP:-/tmp}/certificate.p12"

# Cleanup trap: remove certificate file and delete temporary keychain on exit
cleanup() {
  rm -f "$CERTIFICATE_PATH"
  if security list-keychains -d user | grep -q "$KEYCHAIN_NAME" 2>/dev/null; then
    ORIGINAL_KEYCHAINS=$(security list-keychains -d user | tr -d '"' | grep -v "$KEYCHAIN_NAME" | tr '\n' ' ')
    # shellcheck disable=SC2086
    security list-keychains -d user -s $ORIGINAL_KEYCHAINS 2>/dev/null || true
    security delete-keychain "$KEYCHAIN_NAME" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Validate required secrets are present
if [[ -z "${CERTIFICATE_P12_BASE64:-}" ]]; then
  echo "⚠️  CERTIFICATE_P12_BASE64 is not set — skipping certificate import (ad-hoc signing)"
  # Export variables for downstream steps to use ad-hoc signing
  echo "CODE_SIGN_IDENTITY=-" >> "${GITHUB_ENV:-/dev/null}"
  echo "CODE_SIGNING_REQUIRED=NO" >> "${GITHUB_ENV:-/dev/null}"
  echo "CODE_SIGNING_ALLOWED=NO" >> "${GITHUB_ENV:-/dev/null}"
  exit 0
fi

echo "→ Decoding certificate..."
# Use printf to avoid interpretation of escape sequences in the secret value
printf '%s' "${CERTIFICATE_P12_BASE64}" | base64 --decode > "$CERTIFICATE_PATH"

echo "→ Creating temporary keychain: $KEYCHAIN_NAME"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"
security set-keychain-settings -lut 21600 "$KEYCHAIN_NAME"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"

echo "→ Importing certificate into keychain..."
security import "$CERTIFICATE_PATH" \
  -k "$KEYCHAIN_NAME" \
  -P "${CERTIFICATE_PASSWORD:-}" \
  -T /usr/bin/codesign \
  -T /usr/bin/security

echo "→ Setting keychain access..."
security set-key-partition-list \
  -S apple-tool:,apple: \
  -k "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN_NAME"

echo "→ Adding keychain to search list..."
# Preserve existing keychains; prepend the new one
EXISTING_KEYCHAINS=$(security list-keychains -d user | tr -d '"' | tr '\n' ' ')
# shellcheck disable=SC2086
security list-keychains -d user -s "$KEYCHAIN_NAME" $EXISTING_KEYCHAINS

echo "→ Verifying imported identities..."
IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN_NAME" | head -1 | awk -F '"' '{print $2}')

if [[ -z "$IDENTITY" ]]; then
  echo "✗ No valid signing identity found in keychain"
  exit 1
fi

echo "✓ Found signing identity: $IDENTITY"

# Export for downstream xcodebuild steps
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "CODE_SIGN_IDENTITY=$IDENTITY" >> "$GITHUB_ENV"
  echo "CODE_SIGNING_REQUIRED=YES" >> "$GITHUB_ENV"
  echo "CODE_SIGNING_ALLOWED=YES" >> "$GITHUB_ENV"
  echo "OTHER_CODE_SIGN_FLAGS=--keychain $KEYCHAIN_NAME" >> "$GITHUB_ENV"
  echo "CI_KEYCHAIN_NAME=$KEYCHAIN_NAME" >> "$GITHUB_ENV"
fi

echo "✓ Certificate import complete"
# Disable EXIT trap — keychain must persist for the remainder of the CI job
trap - EXIT
