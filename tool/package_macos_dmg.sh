#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIRECTORY/.." && pwd)"
DEFAULT_SOURCE="$REPOSITORY_ROOT/build/macos/Build/Products/Release/google_code.app"
SOURCE="$DEFAULT_SOURCE"
OUTPUT=""
SKIP_BUILD=false
DRY_RUN=false

usage() {
  cat <<'USAGE'
Create a personal-use macOS DMG containing Google Code.app and an Applications shortcut.

Usage:
  bash tool/package_macos_dmg.sh [options]

Options:
  --source PATH   Release .app bundle to package.
  --output PATH   Destination .dmg path. Defaults to dist/macos/ with versioned name.
  --skip-build    Reuse an existing Flutter macOS Release build.
  --dry-run       Validate inputs and print the intended output without writing files.
  -h, --help      Show this help.

The DMG preserves the app's existing signature, does not remove quarantine metadata,
and is intended only for installation on trusted personal devices.
USAGE
}

log() {
  printf '[Google Code DMG] %s\n' "$*"
}

fail() {
  printf '[Google Code DMG] ERROR: %s\n' "$*" >&2
  exit 1
}

while (($# > 0)); do
  case "$1" in
    --source)
      (($# >= 2)) || fail '--source requires a path.'
      SOURCE="$2"
      shift 2
      ;;
    --output)
      (($# >= 2)) || fail '--output requires a path.'
      OUTPUT="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ "$(uname -s)" == 'Darwin' ]] || fail 'DMG packaging must run on macOS.'
command -v hdiutil >/dev/null 2>&1 || fail 'hdiutil is unavailable.'
command -v codesign >/dev/null 2>&1 || fail 'codesign is unavailable.'
command -v shasum >/dev/null 2>&1 || fail 'shasum is unavailable.'

VERSION_LINE="$(grep -E '^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+(\+[0-9]+)?[[:space:]]*$' "$REPOSITORY_ROOT/pubspec.yaml" | head -n 1 || true)"
[[ -n "$VERSION_LINE" ]] || fail 'Unable to read a valid version from pubspec.yaml.'
VERSION_VALUE="${VERSION_LINE#version:}"
VERSION_VALUE="$(printf '%s' "$VERSION_VALUE" | tr -d '[:space:]')"
APP_VERSION="${VERSION_VALUE%%+*}"
if [[ "$VERSION_VALUE" == *+* ]]; then
  BUILD_NUMBER="${VERSION_VALUE#*+}"
else
  BUILD_NUMBER='0'
fi
PACKAGE_VERSION="${APP_VERSION}-build${BUILD_NUMBER}"

if [[ -z "$OUTPUT" ]]; then
  OUTPUT="$REPOSITORY_ROOT/dist/macos/GoogleCode-${PACKAGE_VERSION}-macos-universal.dmg"
fi
[[ "$OUTPUT" == *.dmg ]] || fail 'Output path must end with .dmg.'
OUTPUT_DIRECTORY="$(dirname "$OUTPUT")"
CHECKSUM_PATH="$OUTPUT.sha256"

if [[ "$SKIP_BUILD" == false ]]; then
  log 'Building macOS Release app...'
  if [[ "$DRY_RUN" == true ]]; then
    log "Would run a Flutter Release build in $REPOSITORY_ROOT."
  else
    cd "$REPOSITORY_ROOT"
    if command -v fvm >/dev/null 2>&1; then
      fvm flutter build macos --release
    elif command -v flutter >/dev/null 2>&1; then
      flutter build macos --release
    else
      fail 'Neither fvm nor flutter is available. Install Flutter or use --skip-build.'
    fi
  fi
fi

[[ -d "$SOURCE" ]] || fail "Source application does not exist: $SOURCE"
[[ -x "$SOURCE/Contents/MacOS/google_code" ]] || fail 'Source application executable is missing.'
codesign --verify --deep --strict "$SOURCE" || fail 'Source application signature verification failed.'

log "Source: $SOURCE"
log "Output: $OUTPUT"
log 'Contents: Google Code.app plus an Applications shortcut.'
log 'Signature expectation: ad hoc/local only; Gatekeeper is not bypassed.'

if [[ "$DRY_RUN" == true ]]; then
  log 'Dry run complete; no files were changed.'
  exit 0
fi

mkdir -p "$OUTPUT_DIRECTORY"
STAGING_DIRECTORY="$(mktemp -d "$OUTPUT_DIRECTORY/.google-code-dmg.XXXXXX")"
TEMPORARY_DMG="$OUTPUT_DIRECTORY/.${OUTPUT##*/}"
TEMPORARY_DMG="${TEMPORARY_DMG%.dmg}.installing-$$.dmg"
cleanup() {
  rm -rf "$STAGING_DIRECTORY"
  rm -f "$TEMPORARY_DMG"
}
trap cleanup EXIT

# ditto preserves the bundle layout, executable bits, extended attributes, and signature.
ditto "$SOURCE" "$STAGING_DIRECTORY/Google Code.app"
ln -s /Applications "$STAGING_DIRECTORY/Applications"

rm -f "$TEMPORARY_DMG"
hdiutil create \
  -volname 'Google Code' \
  -srcfolder "$STAGING_DIRECTORY" \
  -format UDZO \
  -ov \
  "$TEMPORARY_DMG" >/dev/null
hdiutil verify "$TEMPORARY_DMG" >/dev/null
mv -f "$TEMPORARY_DMG" "$OUTPUT"

HASH="$(shasum -a 256 "$OUTPUT" | awk '{print $1}')"
printf '%s  %s\n' "$HASH" "$(basename "$OUTPUT")" > "$CHECKSUM_PATH"

log 'DMG created and verified successfully.'
log "SHA-256: $HASH"
log "Package: $OUTPUT"
log "Checksum: $CHECKSUM_PATH"
