#!/usr/bin/env bash
# ci-archive.sh
# Archives and signs the MiniMaxAgent macOS app in CI.
# Must be run after ci-import-certificate.sh has set CODE_SIGN_IDENTITY.
#
# Optional environment variables:
#   PROVISIONING_PROFILE_BASE64  — base64-encoded .provisionprofile file
#   ARCHIVE_PATH                 — output path for .xcarchive (default: build/MiniMaxAgent.xcarchive)

set -euo pipefail

RUNNER_TEMP="${RUNNER_TEMP:-/tmp}"
ARCHIVE_PATH="${ARCHIVE_PATH:-build/MiniMaxAgent.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-build/export}"
PP_PATH="$RUNNER_TEMP/profile.provisionprofile"
EXPORT_OPTIONS_PLIST="$RUNNER_TEMP/ExportOptions.plist"

# Cleanup trap: remove temporary files created by this script
cleanup() {
  rm -f "$PP_PATH" "$EXPORT_OPTIONS_PLIST"
}
trap cleanup EXIT

# Install provisioning profile if provided
if [[ -n "${PROVISIONING_PROFILE_BASE64:-}" ]]; then
  echo "→ Installing provisioning profile..."
  # Use printf to avoid interpretation of escape sequences in the secret value
  printf '%s' "${PROVISIONING_PROFILE_BASE64}" | base64 --decode > "$PP_PATH"

  PP_UUID=$(grep -a -A1 '<key>UUID</key>' "$PP_PATH" \
    | grep '<string>' \
    | sed 's/.*<string>\(.*\)<\/string>.*/\1/' \
    | head -1)

  if [[ -z "$PP_UUID" ]]; then
    echo "✗ Failed to extract UUID from provisioning profile — file may be corrupt or binary-encoded"
    exit 1
  fi

  PROFILES_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
  mkdir -p "$PROFILES_DIR"
  cp "$PP_PATH" "$PROFILES_DIR/$PP_UUID.provisionprofile"
  echo "✓ Installed provisioning profile: $PP_UUID"
fi

mkdir -p build

echo "→ Archiving..."
xcodebuild archive \
  -project MiniMaxAgent.xcodeproj \
  -scheme MiniMaxAgent \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}" \
  CODE_SIGNING_REQUIRED="${CODE_SIGNING_REQUIRED:-NO}" \
  ENABLE_HARDENED_RUNTIME=YES \
  2>&1 | tail -30

echo "✓ Archive complete: $ARCHIVE_PATH"

# Export (notarization-ready) only if a real signing identity is present
if [[ "${CODE_SIGN_IDENTITY:-}" != "-" && -n "${CODE_SIGN_IDENTITY:-}" ]]; then
  echo "→ Exporting archive..."

  cat > "$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>hardened-runtime</key>
  <true/>
</dict>
</plist>
EOF

  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
    2>&1 | tail -20

  echo "✓ Export complete: $EXPORT_PATH"
else
  echo "⚠️  Skipping export — no Developer ID certificate available"
fi
