#!/bin/bash
#
# Check that a release zip extracts to a valid, notarized GhostCode.app.
#
#   verify-zip.sh <zip>
#
# Extracts with plain `unzip`, not ditto: users don't always use Archive
# Utility, and `._*` AppleDouble files inside the bundle break its signature.
set -euo pipefail

ZIP=${1:?usage: verify-zip.sh <zip>}
[[ -f $ZIP ]] || { echo "verify-zip: no $ZIP" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

/usr/bin/unzip -q "$ZIP" -d "$TMP"
APP="$TMP/GhostCode.app"
[[ -d $APP ]] || { echo "verify-zip: $ZIP has no GhostCode.app at its root" >&2; exit 1; }

STRAY=$(find "$TMP" \( -name '._*' -o -name '.DS_Store' -o -name '__MACOSX' \) -print)
if [[ -n $STRAY ]]; then
    echo "verify-zip: metadata files in $ZIP would break the signature:" >&2
    printf '%s\n' "$STRAY" >&2
    exit 1
fi

codesign --verify --deep --strict "$APP"
xcrun stapler validate -q "$APP"
spctl --assess --type exec "$APP"

echo "verify-zip: $ZIP extracts to a valid, stapled, Gatekeeper-accepted app"
