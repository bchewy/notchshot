#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Notarizes a Developer ID-signed NotchShot.app with Apple and staples the
# ticket, so Gatekeeper opens it without an Open Anyway step, even offline.
#
# Usage: script/notarize.sh path/to/NotchShot.app
# Credentials, in order of preference:
#   NOTCHSHOT_NOTARY_KEY_PATH, NOTCHSHOT_NOTARY_KEY_ID, NOTCHSHOT_NOTARY_ISSUER
#     (an App Store Connect API key; this is what CI uses), or
#   a notarytool keychain profile named by NOTCHSHOT_NOTARY_PROFILE (default "notchshot"),
#     created once with: xcrun notarytool store-credentials notchshot ...
set -euo pipefail

APP="${1:?Pass the NotchShot.app to notarize.}"
SIGNATURE="$(/usr/bin/codesign --display --verbose=2 "$APP" 2>&1 || true)"
if [[ "$SIGNATURE" != *$'\nAuthority=Developer ID Application:'* ]]; then
  echo "Notarization needs a Developer ID Application signature; $APP has none." >&2
  exit 1
fi

if [[ -n "${NOTCHSHOT_NOTARY_KEY_PATH:-}" ]]; then
  CREDENTIALS=(--key "$NOTCHSHOT_NOTARY_KEY_PATH" --key-id "${NOTCHSHOT_NOTARY_KEY_ID:?}" --issuer "${NOTCHSHOT_NOTARY_ISSUER:?}")
else
  CREDENTIALS=(--keychain-profile "${NOTCHSHOT_NOTARY_PROFILE:-notchshot}")
fi

WORK="$(/usr/bin/mktemp -d)"
trap '/bin/rm -rf "$WORK"' EXIT
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/NotchShot.zip"

echo "Submitting to Apple's notary service; this usually takes a few minutes."
/usr/bin/xcrun notarytool submit "$WORK/NotchShot.zip" "${CREDENTIALS[@]}" --wait --timeout 30m \
  --output-format json > "$WORK/result.json" || true
STATUS="$(/usr/bin/plutil -extract status raw -o - "$WORK/result.json" 2>/dev/null || echo unknown)"
ID="$(/usr/bin/plutil -extract id raw -o - "$WORK/result.json" 2>/dev/null || true)"
if [[ "$STATUS" != Accepted ]]; then
  echo "Notarization was not accepted (status: $STATUS)." >&2
  [[ -z "$ID" ]] || /usr/bin/xcrun notarytool log "$ID" "${CREDENTIALS[@]}" >&2 || true
  exit 1
fi

/usr/bin/xcrun stapler staple "$APP"
/usr/bin/xcrun stapler validate "$APP"
/usr/sbin/spctl --assess --type execute --verbose=2 "$APP"
echo "Notarized and stapled $APP (submission $ID)."
