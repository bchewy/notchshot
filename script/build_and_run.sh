#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

MODE="${1:-run}"
case "$MODE" in run|--build-only|--stage-only|--verify|--debug|--logs|--telemetry) ;; *) echo "Usage: $0 [--build-only|--stage-only|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;; esac
APP_NAME="NotchShot"
BUNDLE_ID="com.bchewy.NotchShot"
# Stable tags must match this version (docs/RELEASING.md).
APP_VERSION="0.8.2"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$PROJECT_ROOT/outputs/$APP_NAME.app"
STAGED_APP="$PROJECT_ROOT/work/staged/$APP_NAME.app"
BUILD_CONFIGURATION=debug
BUILD_CHANNEL=Local
if [[ "$MODE" == --stage-only ]]; then
  BUILD_CONFIGURATION=release
  # The updater follows this channel; CI stages Nightly builds of main.
  BUILD_CHANNEL="${NOTCHSHOT_BUILD_CHANNEL:-Stable}"
  if [[ "$BUILD_CHANNEL" != Stable && "$BUILD_CHANNEL" != Nightly ]]; then
    echo "NOTCHSHOT_BUILD_CHANNEL must be Stable or Nightly." >&2
    exit 2
  fi
fi
cd "$PROJECT_ROOT"

mkdir -p "$PROJECT_ROOT/work"
LOCK_DIR="$PROJECT_ROOT/work/build-and-run.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "Another build/run is already in progress ($LOCK_DIR)." >&2
  exit 1
fi
TRANSACTION_DIR=""
PREVIOUS_APP=""
INSTALL_COMMITTED=false
APP_WAS_RUNNING=false
finish() {
  local result=$?
  trap - EXIT
  set +e
  if [[ "$INSTALL_COMMITTED" == false && -n "$PREVIOUS_APP" && -d "$PREVIOUS_APP" ]]; then
    # Move a failed replacement aside before restoring; never delete the old app.
    if [[ -e "$APP_BUNDLE" ]]; then
      mv "$APP_BUNDLE" "$TRANSACTION_DIR/failed.app"
    fi
    if [[ ! -e "$APP_BUNDLE" ]]; then
      if mv "$PREVIOUS_APP" "$APP_BUNDLE"; then
        echo "Restored the previous app at $APP_BUNDLE." >&2
      else
        echo "Restore failed; the previous app is preserved at $PREVIOUS_APP." >&2
        result=1
      fi
    else
      echo "Replacement could not be moved aside; the previous app is preserved at $PREVIOUS_APP." >&2
      result=1
    fi
  fi
  if [[ "$INSTALL_COMMITTED" == false && "$APP_WAS_RUNNING" == true && -d "$APP_BUNDLE" ]]; then
    if ! pgrep -x "$APP_NAME" >/dev/null; then /usr/bin/open -n "$APP_BUNDLE"; fi
  fi
  rmdir "$LOCK_DIR" 2>/dev/null
  exit "$result"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

SIGNING_IDENTITY="${NOTCHSHOT_SIGNING_IDENTITY:-}"
SIGNING_CACHE="$PROJECT_ROOT/work/signing-identity.txt"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  AVAILABLE_IDENTITIES="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null || true)"
  if [[ -f "$SIGNING_CACHE" ]]; then
    SIGNING_IDENTITY="$(cat "$SIGNING_CACHE")"
    if [[ "$AVAILABLE_IDENTITIES" != *"$SIGNING_IDENTITY"* ]]; then
      echo "The saved development signing identity is unavailable. Run with access to your login keychain, or set NOTCHSHOT_SIGNING_IDENTITY explicitly. The installed app has not been changed." >&2
      exit 1
    fi
    SAVED_IDENTITY_STATUS="$(/usr/bin/awk -v identity="$SIGNING_IDENTITY" '$2 == identity { print; exit }' <<< "$AVAILABLE_IDENTITIES")"
    if [[ "$SAVED_IDENTITY_STATUS" == *CSSMERR_* ]]; then
      echo "The saved development certificate has a trust error. Set NOTCHSHOT_SIGNING_IDENTITY to a valid identity before retrying. The installed app has not been changed." >&2
      exit 1
    fi
  else
    # security can list a revoked identity even with -v; do not select entries
    # that it explicitly annotates with certificate-policy errors.
    SIGNING_IDENTITY="$(/usr/bin/awk '/"Apple Development:/ && !/CSSMERR_/ {print $2; exit}' <<< "$AVAILABLE_IDENTITIES")"
    if [[ -n "$SIGNING_IDENTITY" ]]; then
      printf '%s\n' "$SIGNING_IDENTITY" > "$SIGNING_CACHE"
    else
      SIGNING_IDENTITY="-"
      echo "No development signing identity available; using ad-hoc signing. Changed builds may need privacy permissions again."
    fi
  fi
fi

if [[ "$MODE" == --stage-only && "$SIGNING_IDENTITY" == - ]]; then
  echo "Release packaging requires the existing certificate signing identity. No app has been replaced." >&2
  exit 1
fi

mkdir -p "$PROJECT_ROOT/work/clang-cache" "$PROJECT_ROOT/work/swift-cache"
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/work/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/work/swift-cache"
# Record the checkout used for this local build without embedding its disk path.
SOURCE_REVISION="$(git rev-parse --verify HEAD 2>/dev/null || true)"
SOURCE_DIRTY=true
if [[ -n "$SOURCE_REVISION" ]]; then
  if SOURCE_STATUS="$(git status --porcelain --untracked-files=normal)" && [[ -z "$SOURCE_STATUS" ]]; then SOURCE_DIRTY=false; fi
else
  SOURCE_REVISION="unknown"
fi
if [[ "$MODE" == --stage-only && "$SOURCE_DIRTY" == true ]]; then
  echo "Commit the source changes before staging a release so its source revision is exact." >&2
  exit 1
fi
# The commit count only grows on main, so every stable and nightly build is
# numbered above the last. The updater compares these numbers. 0.6.0 was 29.
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
if [[ "$MODE" == --stage-only ]]; then
  if [[ "$(git rev-parse --is-shallow-repository)" != false || "$BUILD_NUMBER" -le 29 ]]; then
    echo "Staging needs the full git history for the build number (fetch-depth: 0 in CI)." >&2
    exit 1
  fi
fi
swift build --configuration "$BUILD_CONFIGURATION" --disable-sandbox
BUILD_BINARY="$(swift build --configuration "$BUILD_CONFIGURATION" --disable-sandbox --show-bin-path)/$APP_NAME"
# Only scratch staging is cleared. The stable app and its running process stay
# untouched until the entire replacement has been built, signed, and verified.
mkdir -p "$PROJECT_ROOT/work/staged"
rm -rf "$STAGED_APP"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BUILD_BINARY" "$STAGED_APP/Contents/MacOS/$APP_NAME"
cp "$PROJECT_ROOT/LICENSE" "$STAGED_APP/Contents/Resources/LICENSE"
cp "$PROJECT_ROOT/LICENSE-MIT" "$STAGED_APP/Contents/Resources/LICENSE-MIT"
cp "$PROJECT_ROOT/LICENSING.md" "$STAGED_APP/Contents/Resources/LICENSING.md"
cp "$PROJECT_ROOT/THIRD_PARTY_NOTICES.md" "$STAGED_APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp "$PROJECT_ROOT"/Sources/NotchShot/Resources/*.wav "$STAGED_APP/Contents/Resources/"
cp "$PROJECT_ROOT"/Sources/NotchShot/Resources/Camera*.png "$STAGED_APP/Contents/Resources/"
# Regenerate with: swift script/make_app_icon.swift
cp "$PROJECT_ROOT/Sources/NotchShot/Resources/AppIcon.icns" "$STAGED_APP/Contents/Resources/AppIcon.icns"
cat > "$STAGED_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSScreenCaptureUsageDescription</key><string>Capture the active app window when you press the shortcut or click Capture.</string>
</dict></plist>
PLIST
# plutil handles string escaping; these fields are part of the signed bundle.
/usr/bin/plutil -insert NotchShotBuildChannel -string "$BUILD_CHANNEL" "$STAGED_APP/Contents/Info.plist"
/usr/bin/plutil -insert NotchShotSourceRevision -string "$SOURCE_REVISION" "$STAGED_APP/Contents/Info.plist"
/usr/bin/plutil -insert NotchShotSourceDirty -bool "$SOURCE_DIRTY" "$STAGED_APP/Contents/Info.plist"

# Reuse a development identity when available so macOS sees updates as the same
# app. The cached value is a public certificate fingerprint, never a private key.
if ! /usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none --identifier "$BUNDLE_ID" "$STAGED_APP"; then
  echo "Signing failed. The new app was not installed; the existing app has not been stopped or replaced." >&2
  echo "The staged build is at $STAGED_APP. Resolve the reported signing error before retrying this command." >&2
  exit 1
fi
/usr/bin/codesign --verify --strict "$STAGED_APP"

# Signature integrity alone does not establish that the signer is still trusted.
# Check the embedded public certificate chain without applying Gatekeeper's
# distribution/notarization policy to this local development app.
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  CERTIFICATE_DIR="$(mktemp -d "$PROJECT_ROOT/work/staged/signing-check.XXXXXX")"
  CERTIFICATE_PREFIX="$CERTIFICATE_DIR/cert"
  if ! /usr/bin/codesign --display --extract-certificates="$CERTIFICATE_PREFIX" "$STAGED_APP"; then
    echo "Could not extract the signing certificate chain. The app was not installed; the existing app has not been stopped or replaced." >&2
    exit 1
  fi
  VERIFY_CERT_ARGS=(-p codeSign -R ocsp -R require)
  CERTIFICATE_INDEX=0
  while [[ -f "$CERTIFICATE_PREFIX$CERTIFICATE_INDEX" ]]; do
    VERIFY_CERT_ARGS+=(-c "$CERTIFICATE_PREFIX$CERTIFICATE_INDEX")
    CERTIFICATE_INDEX=$((CERTIFICATE_INDEX + 1))
  done
  if [[ "$CERTIFICATE_INDEX" -eq 0 ]]; then
    echo "No signing certificate was found. Only the ad-hoc identity '-' may skip certificate validation; the app was not installed." >&2
    exit 1
  fi
  # Requiring a positive OCSP response prevents an unknown status from silently
  # passing. A valid cached response can suffice; unavailable status blocks an
  # offline build from replacing the installed app until verification succeeds.
  if ! /usr/bin/security verify-cert "${VERIFY_CERT_ARGS[@]}"; then
    echo "Signing certificate trust or revocation verification failed. The app was not installed; the existing app has not been stopped or replaced." >&2
    echo "A positive OCSP status is required. Check the reported certificate error or network availability before retrying. Public certificates are saved at $CERTIFICATE_DIR." >&2
    exit 1
  fi
fi

if [[ "$MODE" == --stage-only ]]; then
  echo "Verified $BUILD_CHANNEL $STAGED_APP ($SOURCE_REVISION); the installed app is unchanged."
  exit 0
fi

# Copy onto the destination filesystem before stopping the app, so installation
# itself consists of renames. Keep the previous complete bundle as a backup.
mkdir -p "$PROJECT_ROOT/outputs"
TRANSACTION_DIR="$(mktemp -d "$PROJECT_ROOT/outputs/.notchshot-update.XXXXXX")"
REPLACEMENT_APP="$TRANSACTION_DIR/$APP_NAME.app"
PREVIOUS_APP="$TRANSACTION_DIR/previous.app"
/usr/bin/ditto "$STAGED_APP" "$REPLACEMENT_APP"
/usr/bin/codesign --verify --strict "$REPLACEMENT_APP"
if pgrep -x "$APP_NAME" >/dev/null; then APP_WAS_RUNNING=true; fi
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
for _ in {1..50}; do
  if ! pgrep -x "$APP_NAME" >/dev/null; then break; fi
  sleep 0.1
done
if pgrep -x "$APP_NAME" >/dev/null; then
  echo "The app did not stop; its installed bundle has not been changed." >&2
  exit 1
fi
if [[ -e "$APP_BUNDLE" ]]; then mv "$APP_BUNDLE" "$PREVIOUS_APP"; fi
mv "$REPLACEMENT_APP" "$APP_BUNDLE"
/usr/bin/codesign --verify --strict "$APP_BUNDLE"
INSTALL_COMMITTED=true

case "$MODE" in
  --build-only) echo "Built $APP_BUNDLE" ;;
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --verify)
    /usr/bin/open -n "$APP_BUNDLE"
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    echo "Build, signature, and running process verified: $APP_BUNDLE"
    ;;
  --debug)
    /usr/bin/open -n "$APP_BUNDLE"
    sleep 1
    lldb -n "$APP_NAME"
    ;;
  --logs)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'process == "NotchShot"'
    ;;
  --telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.bchewy.NotchShot"'
    ;;
esac
