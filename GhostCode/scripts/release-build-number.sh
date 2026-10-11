#!/bin/bash
#
# Print the CFBundleVersion for a release build.
#
#   release-build-number.sh <run-number> [previous-appcast]
#
# A new version uses the workflow run number. A re-run of a version that is
# already published passes that release's appcast.xml and keeps its build
# number: Sparkle compares build numbers, so a higher one would offer the same
# version again as an "update" to everyone already on it.
set -euo pipefail

RUN_NUMBER=${1:?usage: release-build-number.sh <run-number> [previous-appcast]}
PREVIOUS=${2:-}

[[ $RUN_NUMBER =~ ^[0-9]+$ ]] || { echo "release-build-number: run number '$RUN_NUMBER' is not a number" >&2; exit 1; }

if [[ -z $PREVIOUS || ! -e $PREVIOUS ]]; then
    echo "$RUN_NUMBER"
    exit 0
fi

BUILD=$(/usr/bin/sed -n 's:.*<sparkle\:version>\([^<]*\)</sparkle\:version>.*:\1:p' "$PREVIOUS" | head -n 1)
[[ $BUILD =~ ^[0-9]+$ ]] || { echo "release-build-number: no numeric sparkle:version in $PREVIOUS" >&2; exit 1; }
echo "$BUILD"
