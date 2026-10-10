#!/bin/bash
# Run: GhostCode/scripts/tests/test-verify-ed-signature.sh
# Generates a throwaway Ed25519 key with CryptoKit, signs a temp file, and checks
# that verify-ed-signature.swift accepts it and rejects a changed file or wrong key.
set -euo pipefail
cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf 'ghostcode update' > "$TMP/update.zip"

cat > "$TMP/sign.swift" <<'SWIFT'
import CryptoKit
import Foundation
let key = Curve25519.Signing.PrivateKey()
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let signature = try key.signature(for: data)
print(signature.base64EncodedString())
print(key.publicKey.rawRepresentation.base64EncodedString())
print(Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString())
SWIFT
{ read -r SIG; read -r PUB; read -r OTHER; } < <(swift "$TMP/sign.swift" "$TMP/update.zip")

swift verify-ed-signature.swift "$TMP/update.zip" "$SIG" "$PUB"

printf 'tampered' >> "$TMP/update.zip"
if swift verify-ed-signature.swift "$TMP/update.zip" "$SIG" "$PUB" 2>/dev/null; then
    echo "FAIL: accepted a changed file" >&2; exit 1
fi
printf 'ghostcode update' > "$TMP/update.zip"
if swift verify-ed-signature.swift "$TMP/update.zip" "$SIG" "$OTHER" 2>/dev/null; then
    echo "FAIL: accepted the wrong public key" >&2; exit 1
fi
if swift verify-ed-signature.swift "$TMP/update.zip" "not-base64" "$PUB" 2>/dev/null; then
    echo "FAIL: accepted a malformed signature" >&2; exit 1
fi
echo "test-verify-ed-signature: ok"
