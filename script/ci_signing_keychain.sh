#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# CI only: import the release signing certificate into a temporary keychain,
# then delete it. Local builds never use this. See docs/RELEASING.md.
set -euo pipefail

KEYCHAIN="${RUNNER_TEMP:?RUNNER_TEMP is set by GitHub Actions}/notchshot-signing.keychain-db"

case "${1:-}" in
  import)
    : "${NOTCHSHOT_SIGNING_P12_BASE64:?Add the NOTCHSHOT_SIGNING_P12_BASE64 repository secret (docs/RELEASING.md).}"
    : "${NOTCHSHOT_SIGNING_P12_PASSWORD:?Add the NOTCHSHOT_SIGNING_P12_PASSWORD repository secret (docs/RELEASING.md).}"
    CERTIFICATE="$RUNNER_TEMP/notchshot-signing.p12"
    INTERMEDIATE="$RUNNER_TEMP/AppleWWDRCAG3.cer"
    trap 'rm -f "$CERTIFICATE" "$INTERMEDIATE"' EXIT
    KEYCHAIN_PASSWORD="$(uuidgen)"
    printf '%s' "$NOTCHSHOT_SIGNING_P12_BASE64" | base64 --decode > "$CERTIFICATE"
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    security set-keychain-settings -lut 21600 "$KEYCHAIN"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    echo "Importing the signing identity."
    security import "$CERTIFICATE" -k "$KEYCHAIN" -f pkcs12 -P "$NOTCHSHOT_SIGNING_P12_PASSWORD" -T /usr/bin/codesign
    # Apple Development certificates chain through the WWDR G3 intermediate;
    # codesign embeds it, and the build script checks the chain with OCSP.
    # Runner images may already install it, and import then reports a duplicate.
    echo "Importing the WWDR G3 intermediate."
    curl -fsSL https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer -o "$INTERMEDIATE"
    if ! output="$(security import "$INTERMEDIATE" -k "$KEYCHAIN" 2>&1)"; then
      if [[ "$output" != *"already exists"* ]]; then
        echo "$output" >&2
        exit 1
      fi
      echo "The WWDR G3 intermediate is already installed."
    fi
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
    security list-keychains -d user -s "$KEYCHAIN"
    # A Developer ID certificate (notarized releases) wins over Apple Development.
    IDENTITIES="$(security find-identity -v -p codesigning "$KEYCHAIN")"
    IDENTITY="$(awk '/"Developer ID Application:/ && !/CSSMERR_/ {print $2; exit}' <<< "$IDENTITIES")"
    [[ -n "$IDENTITY" ]] || IDENTITY="$(awk '/"Apple Development:/ && !/CSSMERR_/ {print $2; exit}' <<< "$IDENTITIES")"
    if [[ -z "$IDENTITY" ]]; then
      echo "::error::The signing secret holds no valid Developer ID Application or Apple Development identity."
      exit 1
    fi
    echo "NOTCHSHOT_SIGNING_IDENTITY=$IDENTITY" >> "$GITHUB_ENV"
    echo "Imported signing identity $IDENTITY."
    ;;
  cleanup)
    security delete-keychain "$KEYCHAIN" 2>/dev/null || true
    ;;
  *)
    echo "Usage: $0 import|cleanup" >&2
    exit 2
    ;;
esac
