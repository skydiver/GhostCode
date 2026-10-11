#!/bin/bash
# Run: GhostCode/scripts/tests/test-make-appcast.sh
set -euo pipefail
cd "$(dirname "$0")/.."

NOTES=$(mktemp)
trap 'rm -f "$NOTES"' EXIT
cat > "$NOTES" <<'MD'
## What's New

- First & best
- Edge: ]]> inside
MD

ATTRS='sparkle:edSignature="c2ln" length="123"'
OUT=$(./make-appcast.sh 0.15.1 42 13.0 "$ATTRS" "$NOTES")
printf '%s' "$OUT" | xmllint --noout -
expect() { [[ $OUT == *"$1"* ]] || { echo "FAIL: missing $1" >&2; exit 1; }; }
expect '<sparkle:version>42</sparkle:version>'
expect '<sparkle:shortVersionString>0.15.1</sparkle:shortVersionString>'
expect '<sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>'
expect 'url="https://github.com/skydiver/GhostCode/releases/download/v0.15.1/GhostCode-0.15.1-universal.zip"'
expect 'sparkle:edSignature="c2ln" length="123"'
expect '<description sparkle:format="markdown"><![CDATA[## What'"'"'s New'
expect '- First & best'
expect ']]]]><![CDATA[>'
[[ $OUT != *releaseNotesLink* ]] || { echo "FAIL: releaseNotesLink present" >&2; exit 1; }

if ./make-appcast.sh 0.15.1 42 13.0 'length="123"' "$NOTES" >/dev/null 2>&1; then
    echo "FAIL: accepted attributes without a signature" >&2; exit 1
fi
# Without a notes file the item has no description (notes are added to the
# GitHub release by hand after publishing).
BARE=$(./make-appcast.sh 0.15.1 42 13.0 "$ATTRS")
printf '%s' "$BARE" | xmllint --noout -
[[ $BARE == *'<sparkle:version>42</sparkle:version>'* ]] || { echo "FAIL: no version without notes" >&2; exit 1; }
[[ $BARE != *'sparkle:format="markdown"'* ]] || { echo "FAIL: notes present without a notes file" >&2; exit 1; }
if ./make-appcast.sh 0.15.1 42 13.0 "$ATTRS" /nonexistent/notes.md >/dev/null 2>&1; then
    echo "FAIL: accepted a nonexistent notes file" >&2; exit 1
fi
echo "test-make-appcast: ok"
