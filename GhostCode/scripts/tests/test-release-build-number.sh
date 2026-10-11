#!/bin/bash
# Run: GhostCode/scripts/tests/test-release-build-number.sh
set -euo pipefail
cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

expect_out() {
    local want=$1; shift
    local got
    got=$(./release-build-number.sh "$@") || { echo "FAIL: exited non-zero for: $*" >&2; exit 1; }
    [[ $got == "$want" ]] || { echo "FAIL: '$*' printed '$got', want '$want'" >&2; exit 1; }
}
expect_fail() {
    if ./release-build-number.sh "$@" >/dev/null 2>&1; then
        echo "FAIL: accepted: $*" >&2; exit 1
    fi
}

# First release of a version: the run number.
expect_out 57 57
expect_out 57 57 "$TMP/missing.xml"

# Re-run of a published release: keep the build number users already have.
NOTES="$TMP/notes.md"
echo "- Notes" > "$NOTES"
./make-appcast.sh 0.15.1 42 13.0 'sparkle:edSignature="c2ln" length="1"' "$NOTES" > "$TMP/appcast.xml"
expect_out 42 57 "$TMP/appcast.xml"

# An appcast without a usable build number is an error, not a silent fallback.
echo '<rss><channel><item><sparkle:version>abc</sparkle:version></item></channel></rss>' > "$TMP/bad.xml"
expect_fail 57 "$TMP/bad.xml"
echo '<rss/>' > "$TMP/empty.xml"
expect_fail 57 "$TMP/empty.xml"

expect_fail
expect_fail abc
echo "test-release-build-number: ok"
