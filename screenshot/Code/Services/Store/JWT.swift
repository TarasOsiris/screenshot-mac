import Foundation

/// The JWT wire format both store auth services build by hand.
///
/// Only the signature algorithm differs between them — App Store Connect signs ES256 with
/// CryptoKit, Google Play signs RS256 with Security — so this covers assembly only and leaves
/// signing to the caller. Keys are sorted so the encoded payload is deterministic.
nonisolated enum JWT {
    /// `base64url(header) + "." + base64url(claims)` — the bytes that get signed.
    static func signingInput(header: [String: Any], claims: [String: Any]) throws -> String {
        let headerJSON = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        let claimsJSON = try JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys])
        return headerJSON.base64URLEncodedString + "." + claimsJSON.base64URLEncodedString
    }

    static func token(signingInput: String, signature: Data) -> String {
        signingInput + "." + signature.base64URLEncodedString
    }
}
