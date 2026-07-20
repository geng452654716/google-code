#!/usr/bin/env bash

# Installs Google Code for the current macOS user without modifying system-wide
# locations. Re-running the script performs a recoverable in-place upgrade.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_SOURCE="$REPO_ROOT/build/macos/Build/Products/Release/google_code.app"
DEFAULT_DESTINATION="$HOME/Applications/Google Code.app"
APP_EXECUTABLE_RELATIVE="Contents/MacOS/google_code"

source_app="$DEFAULT_SOURCE"
destination_app="$DEFAULT_DESTINATION"
skip_build=false
launch_after_install=false
uninstall=false
dry_run=false
codesign_identity="${GOOGLE_CODE_CODESIGN_IDENTITY:-}"

usage() {
  cat <<'USAGE'
Usage: bash tool/install_macos.sh [options]

Installs Google Code for the current user. Existing installations are replaced
through staging and backup directories so a failed upgrade can be restored.

Options:
  --source PATH       Source .app bundle. Defaults to the local Release build.
  --destination PATH  Install path. Defaults to ~/Applications/Google Code.app.
  --skip-build        Do not run a Flutter Release build before installation.
  --codesign-identity NAME
                      Re-sign with a stable local identity before installation.
                      Defaults to GOOGLE_CODE_CODESIGN_IDENTITY when set.
  --launch            Launch the installed app after a successful install.
  --uninstall         Remove the installed app. Vault and backup data are kept.
  --dry-run           Validate and print the plan without changing files.
  -h, --help          Show this help.

Security notes:
  Without a stable identity the local build remains ad hoc signed, so macOS may
  require privacy permission again after an upgrade.
  This script never removes com.apple.quarantine and never bypasses Gatekeeper.
USAGE
}

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

log() {
  printf '[Google Code installer] %s\n' "$1"
}

require_value() {
  local option="$1"
  local value="${2:-}"
  if [[ -z "$value" ]]; then
    fail "$option requires a path."
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      require_value "$1" "${2:-}"
      source_app="$2"
      shift 2
      ;;
    --destination)
      require_value "$1" "${2:-}"
      destination_app="$2"
      shift 2
      ;;
    --skip-build)
      skip_build=true
      shift
      ;;
    --codesign-identity)
      require_value "$1" "${2:-}"
      codesign_identity="$2"
      shift 2
      ;;
    --launch)
      launch_after_install=true
      shift
      ;;
    --uninstall)
      uninstall=true
      shift
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

if [[ "$destination_app" != *.app ]]; then
  fail 'Destination must be an .app path.'
fi
if [[ "$destination_app" == "/" || -z "$destination_app" ]]; then
  fail 'Unsafe destination path.'
fi
if [[ "$source_app" == "$destination_app" ]]; then
  fail 'Source and destination must be different paths.'
fi
if $uninstall && $launch_after_install; then
  fail '--launch cannot be combined with --uninstall.'
fi

if pgrep -x google_code >/dev/null 2>&1; then
  fail 'Google Code is running. Quit it before installing, upgrading, or uninstalling.'
fi

if $uninstall; then
  log "Uninstall target: $destination_app"
  log 'Vault, Keychain entries, and .gcbak files will not be removed.'
  if $dry_run; then
    log 'Dry run complete; no files were changed.'
    exit 0
  fi
  if [[ -e "$destination_app" || -L "$destination_app" ]]; then
    rm -rf "$destination_app"
    log 'Application removed. User data was preserved.'
  else
    log 'Application is not installed; nothing to remove.'
  fi
  exit 0
fi

if ! $skip_build; then
  log 'Building macOS Release app...'
  if $dry_run; then
    log "Would run a Flutter Release build in $REPO_ROOT."
  elif command -v fvm >/dev/null 2>&1; then
    (cd "$REPO_ROOT" && fvm flutter build macos --release)
  elif command -v flutter >/dev/null 2>&1; then
    (cd "$REPO_ROOT" && flutter build macos --release)
  else
    fail 'Neither fvm nor flutter is available. Install Flutter or use --skip-build.'
  fi
fi

if [[ ! -d "$source_app" ]]; then
  fail "Source app does not exist: $source_app"
fi
if [[ ! -x "$source_app/$APP_EXECUTABLE_RELATIVE" ]]; then
  fail "Source app executable is missing: $source_app/$APP_EXECUTABLE_RELATIVE"
fi

log "Source: $source_app"
log "Destination: $destination_app"
log 'Install scope: current user only; no administrator privileges are requested.'
if [[ -n "$codesign_identity" ]]; then
  log "Signature identity: $codesign_identity"
  log 'A stable identity helps macOS retain screen-recording permission across upgrades.'
else
  log 'Signature expectation: ad hoc/local only; privacy permissions may need renewal after upgrades.'
fi
log 'Gatekeeper is not bypassed.'

if $dry_run; then
  log 'Dry run complete; no files were changed.'
  exit 0
fi

command -v ditto >/dev/null 2>&1 || fail 'macOS ditto command is required.'
command -v codesign >/dev/null 2>&1 || fail 'macOS codesign command is required.'

parent_directory="$(dirname "$destination_app")"
transaction_id="$$-$(date +%s)"
staging_app="${destination_app}.installing-${transaction_id}"
backup_app="${destination_app}.backup-${transaction_id}"
backup_created=false
install_completed=false

cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM
  if [[ -e "$staging_app" || -L "$staging_app" ]]; then
    rm -rf "$staging_app"
  fi
  if $backup_created && ! $install_completed; then
    if [[ -e "$destination_app" || -L "$destination_app" ]]; then
      rm -rf "$destination_app"
    fi
    mv "$backup_app" "$destination_app"
    log 'Upgrade failed; the previous installation was restored.' >&2
  elif [[ -e "$backup_app" || -L "$backup_app" ]]; then
    rm -rf "$backup_app"
  fi
  exit "$exit_code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$parent_directory"
rm -rf "$staging_app" "$backup_app"
ditto "$source_app" "$staging_app"

if [[ ! -x "$staging_app/$APP_EXECUTABLE_RELATIVE" ]]; then
  fail 'Staged application is incomplete.'
fi
if [[ -n "$codesign_identity" ]]; then
  codesign \
    --force \
    --deep \
    --timestamp=none \
    --preserve-metadata=identifier,entitlements \
    --sign "$codesign_identity" \
    "$staging_app"
fi
codesign --verify --deep --strict "$staging_app"

if [[ -e "$destination_app" || -L "$destination_app" ]]; then
  mv "$destination_app" "$backup_app"
  backup_created=true
fi
mv "$staging_app" "$destination_app"
install_completed=true

if [[ -e "$backup_app" || -L "$backup_app" ]]; then
  rm -rf "$backup_app"
fi
backup_created=false

log 'Installation completed successfully.'
if $launch_after_install; then
  open "$destination_app"
  log 'Application launch requested.'
else
  log "Open it from Finder or run: open \"$destination_app\""
fi
