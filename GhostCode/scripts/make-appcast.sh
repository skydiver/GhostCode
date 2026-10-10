#!/bin/bash
#
# Write a one-item Sparkle appcast for a GhostCode release to stdout.
#
#   make-appcast.sh <version> <build> <min-os> <signed-attrs>
#
# `signed-attrs` is sign_update's output, the literal
# `sparkle:edSignature="…" length="…"` pair. One item is enough: Sparkle only
# needs the newest release, and the feed URL always resolves to the latest one.
set -euo pipefail

VERSION=${1:?usage: make-appcast.sh <version> <build> <min-os> <signed-attrs>}
BUILD=${2:?missing build}
MIN_OS=${3:?missing minimum system version}
SIGNED=${4:?missing signature attributes}

[[ $SIGNED == *edSignature=* ]] || { echo "make-appcast: no signature in '$SIGNED'" >&2; exit 1; }

REPO=https://github.com/skydiver/GhostCode
ZIP_URL="$REPO/releases/download/v$VERSION/GhostCode-$VERSION-universal.zip"
NOTES_URL="$REPO/releases/tag/v$VERSION"

escape() { printf '%s' "$1" | /usr/bin/sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }

cat <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>GhostCode</title>
    <description>GhostCode updates</description>
    <language>en</language>
    <item>
      <title>GhostCode $(escape "$VERSION")</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$(escape "$BUILD")</sparkle:version>
      <sparkle:shortVersionString>$(escape "$VERSION")</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$(escape "$MIN_OS")</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>$(escape "$NOTES_URL")</sparkle:releaseNotesLink>
      <enclosure url="$(escape "$ZIP_URL")" type="application/octet-stream" $SIGNED />
    </item>
  </channel>
</rss>
XML
