#!/bin/bash
# Run: GhostCode/scripts/tests/test-make-appcast.sh
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=$(./make-appcast.sh 0.15.0 42 13.0 'sparkle:edSignature="c2ln" length="123"')
printf '%s' "$OUT" | xmllint --noout -
expect() { [[ $OUT == *"$1"* ]] || { echo "FAIL: missing $1" >&2; exit 1; }; }
expect '<sparkle:version>42</sparkle:version>'
expect '<sparkle:shortVersionString>0.15.0</sparkle:shortVersionString>'
expect '<sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>'
expect '<sparkle:releaseNotesLink>https://github.com/skydiver/GhostCode/releases/tag/v0.15.0</sparkle:releaseNotesLink>'
expect 'url="https://github.com/skydiver/GhostCode/releases/download/v0.15.0/GhostCode-0.15.0-universal.zip"'
expect 'sparkle:edSignature="c2ln" length="123"'

if ./make-appcast.sh 0.15.0 42 13.0 'length="123"' >/dev/null 2>&1; then
    echo "FAIL: accepted attributes without a signature" >&2; exit 1
fi
echo "test-make-appcast: ok"
