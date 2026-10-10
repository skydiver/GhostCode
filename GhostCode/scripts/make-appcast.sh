#!/bin/bash
#
# Write a one-item Sparkle appcast for a GhostCode release to stdout.
#
#   make-appcast.sh <version> <build> <min-os> <signed-attrs> <notes-file>
#
# `signed-attrs` is sign_update's output, the literal
# `sparkle:edSignature="…" length="…"` pair. `notes-file` is the release notes
# in Markdown; they are embedded inline in the item (a signed feed can't use a
# separate releaseNotesLink page, whose content the signature wouldn't cover).
# One item is enough: Sparkle only needs the newest release, and the feed URL
# always resolves to the latest one.
set -euo pipefail

VERSION=${1:?usage: make-appcast.sh <version> <build> <min-os> <signed-attrs> <notes-file>}
BUILD=${2:?missing build}
MIN_OS=${3:?missing minimum system version}
SIGNED=${4:?missing signature attributes}
NOTES_FILE=${5:?missing release notes file}

[[ $SIGNED == *edSignature=* ]] || { echo "make-appcast: no signature in '$SIGNED'" >&2; exit 1; }
[[ -s $NOTES_FILE ]] || { echo "make-appcast: release notes file '$NOTES_FILE' is missing or empty" >&2; exit 1; }
NOTES=$(cat "$NOTES_FILE")
# Keep the notes from closing the CDATA section early.
NOTES=${NOTES//']]>'/']]]]><![CDATA[>'}

REPO=https://github.com/skydiver/GhostCode
ZIP_URL="$REPO/releases/download/v$VERSION/GhostCode-$VERSION-universal.zip"

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
      <description sparkle:format="markdown"><![CDATA[$NOTES]]></description>
      <enclosure url="$(escape "$ZIP_URL")" type="application/octet-stream" $SIGNED />
    </item>
  </channel>
</rss>
XML
