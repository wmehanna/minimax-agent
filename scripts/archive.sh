#!/usr/bin/env bash
# archive.sh
# Local xcodebuild archive and export script for MiniMaxAgent.
#
# Usage:
#   ./scripts/archive.sh [--export] [--export-method <method>]
#
# Options:
#   --export                  Export the archive after archiving (requires signing)
#   --export-method <method>  Export method: developer-id (default), app-store, development
#   --archive-path <path>     Output path for .xcarchive (default: build/MiniMaxAgent.xcarchive)
#   --export-path <path>      Output path for exported app (default: build/export)
#   --configuration <cfg>     Build configuration (default: Release)
#
# Environment variables:
#   CODE_SIGN_IDENTITY        Signing identity (default: ad-hoc "-")
#   TEAM_ID                   Apple Developer Team ID (required for real signing)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults
ARCHIVE_PATH="${ARCHIVE_PATH:-$PROJECT_DIR/build/MiniMaxAgent.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$PROJECT_DIR/build/export}"
CONFIGURATION="${CONFIGURATION:-Release}"
EXPORT_METHOD="${EXPORT_METHOD:-developer-id}"
DO_EXPORT=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --export)
      DO_EXPORT=true
      shift
      ;;
    --export-method)
      EXPORT_METHOD="$2"
      shift 2
      ;;
    --archive-path)
      ARCHIVE_PATH="$2"
      shift 2
      ;;
    --export-path)
      EXPORT_PATH="$2"
      shift 2
      ;;
    --configuration)
      CONFIGURATION="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

echo "=== MiniMaxAgent Archive ==="
echo "  Project:       $PROJECT_DIR/MiniMaxAgent.xcodeproj"
echo "  Configuration: $CONFIGURATION"
echo "  Archive path:  $ARCHIVE_PATH"
echo "  Signing:       ${CODE_SIGN_IDENTITY}"
echo ""

mkdir -p "$(dirname "$ARCHIVE_PATH")"

# Archive
echo "→ Running xcodebuild archive..."
xcodebuild archive \
  -project "$PROJECT_DIR/MiniMaxAgent.xcodeproj" \
  -scheme MiniMaxAgent \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
  CODE_SIGNING_REQUIRED="${CODE_SIGNING_REQUIRED:-NO}" \
  ENABLE_HARDENED_RUNTIME=YES \
  SKIP_INSTALL=NO \
  BUILD_LIBRARIES_FOR_DISTRIBUTION=YES \
  2>&1 | grep -E '(error:|warning:|Archive|BUILD|FAILED|Succeeded)' || true

if [[ ! -d "$ARCHIVE_PATH" ]]; then
  echo "✗ Archive failed — $ARCHIVE_PATH not found"
  exit 1
fi

echo "✓ Archive complete: $ARCHIVE_PATH"

# Export
if [[ "$DO_EXPORT" == "true" ]]; then
  if [[ "$CODE_SIGN_IDENTITY" == "-" ]]; then
    echo "✗ Export requires a real signing identity. Set CODE_SIGN_IDENTITY."
    exit 1
  fi

  EXPORT_OPTIONS_PLIST="$(mktemp /tmp/ExportOptions.XXXXXX.plist)"
  trap 'rm -f "$EXPORT_OPTIONS_PLIST"' EXIT

  TEAM_ID="${TEAM_ID:-}"
  TEAM_ID_ENTRY=""
  if [[ -n "$TEAM_ID" ]]; then
    TEAM_ID_ENTRY="<key>teamID</key><string>$TEAM_ID</string>"
  fi

  cat > "$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>${EXPORT_METHOD}</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>hardened-runtime</key>
  <true/>
  <key>stripSwiftSymbols</key>
  <true/>
  ${TEAM_ID_ENTRY}
</dict>
</plist>
EOF

  mkdir -p "$EXPORT_PATH"

  echo "→ Exporting archive (method: $EXPORT_METHOD)..."
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
    2>&1 | grep -E '(error:|warning:|Export|BUILD|FAILED|Succeeded)' || true

  echo "✓ Export complete: $EXPORT_PATH"
else
  echo ""
  echo "Tip: Run with --export to also export the archive."
  echo "     Requires CODE_SIGN_IDENTITY set to a valid Developer ID."
fi
