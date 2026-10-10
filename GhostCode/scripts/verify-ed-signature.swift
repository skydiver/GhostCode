// Verify a Sparkle EdDSA (Ed25519) signature against a public key.
//
//   swift verify-ed-signature.swift <file> <base64-signature> <base64-public-key>
//
// The release workflow signs with the private key from a secret, then checks the
// signature against SUPublicEDKey read from the built app. A key mismatch would
// otherwise look exactly like "no update available" to every installed copy.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("verify-ed-signature: \(message)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 4 else { fail("usage: verify-ed-signature.swift <file> <signature> <public-key>") }

guard let data = try? Data(contentsOf: URL(fileURLWithPath: args[1]), options: .mappedIfSafe) else {
    fail("cannot read \(args[1])")
}
guard let signature = Data(base64Encoded: args[2]) else { fail("signature is not base64") }
guard let keyData = Data(base64Encoded: args[3]),
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
    fail("public key is not a base64 Ed25519 key")
}
guard publicKey.isValidSignature(signature, for: data) else {
    fail("signature does not match the public key (wrong signing key?)")
}
print("verify-ed-signature: signature matches SUPublicEDKey")
