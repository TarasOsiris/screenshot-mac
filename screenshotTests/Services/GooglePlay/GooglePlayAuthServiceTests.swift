#if DEBUG
import Testing
import Foundation
import Security
@testable import Screenshot_Bro

struct GooglePlayAuthServiceTests {

    // MARK: - Helpers

    /// A freshly generated RSA key with its PKCS#1 (RSA PRIVATE KEY) and PKCS#8 (PRIVATE KEY) PEMs.
    private struct TestKey {
        let privateKey: SecKey
        let publicKey: SecKey
        let pkcs1DER: Data
        let pkcs1PEM: String
        let pkcs8DER: Data
        let pkcs8PEM: String
    }

    private func makeTestKey() throws -> TestKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ]
        var error: Unmanaged<CFError>?
        let priv = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, &error))
        let pub = try #require(SecKeyCopyPublicKey(priv))
        let pkcs1 = try #require(SecKeyCopyExternalRepresentation(priv, &error) as Data?)
        let pkcs8 = Self.wrapPKCS8(pkcs1: pkcs1)
        return TestKey(
            privateKey: priv,
            publicKey: pub,
            pkcs1DER: pkcs1,
            pkcs1PEM: Self.pem(pkcs1, label: "RSA PRIVATE KEY"),
            pkcs8DER: pkcs8,
            pkcs8PEM: Self.pem(pkcs8, label: "PRIVATE KEY")
        )
    }

    private static func derLength(_ n: Int) -> [UInt8] {
        if n < 0x80 { return [UInt8(n)] }
        var bytes: [UInt8] = []
        var value = n
        while value > 0 { bytes.insert(UInt8(value & 0xFF), at: 0); value >>= 8 }
        return [UInt8(0x80 | bytes.count)] + bytes
    }

    /// Wraps a PKCS#1 RSAPrivateKey in a PKCS#8 PrivateKeyInfo (rsaEncryption).
    private static func wrapPKCS8(pkcs1: Data) -> Data {
        let version: [UInt8] = [0x02, 0x01, 0x00]
        let algId: [UInt8] = [0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00]
        let key = [UInt8](pkcs1)
        let octet = [0x04] + derLength(key.count) + key
        let inner = version + algId + octet
        let outer = [0x30] + derLength(inner.count) + inner
        return Data(outer)
    }

    private static func pem(_ der: Data, label: String) -> String {
        let b64 = der.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN \(label)-----\n\(b64)\n-----END \(label)-----\n"
    }

    private func base64urlDecode(_ s: String) -> Data {
        var str = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while str.count % 4 != 0 { str += "=" }
        return Data(base64Encoded: str) ?? Data()
    }

    private func account(pem: String) -> GooglePlayCredentialsStore.ServiceAccount {
        GooglePlayCredentialsStore.ServiceAccount(
            clientEmail: "robot@demo.iam.gserviceaccount.com",
            privateKeyPEM: pem,
            privateKeyId: "kid-123",
            tokenURI: "https://oauth2.googleapis.com/token"
        )
    }

    // MARK: - Tests

    @Test func base64URLHasNoPaddingOrUnsafeChars() {
        let encoded = GooglePlayAuthService.base64URL(Data([0xFB, 0xFF, 0xFE]))
        #expect(!encoded.contains("="))
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
    }

    @Test func pkcs1FromPKCS8RecoversInnerKey() throws {
        let key = try makeTestKey()
        let recovered = try #require(GooglePlayAuthService.pkcs1FromPKCS8(key.pkcs8DER))
        #expect(recovered == key.pkcs1DER)
    }

    @Test func parsesPKCS1PEM() throws {
        let key = try makeTestKey()
        let parsed = try GooglePlayAuthService.rsaPrivateKey(fromPEM: key.pkcs1PEM)
        // Round-trip: the parsed key should match the original by external representation.
        var error: Unmanaged<CFError>?
        let data = try #require(SecKeyCopyExternalRepresentation(parsed, &error) as Data?)
        #expect(data == key.pkcs1DER)
    }

    @Test func parsesPKCS8PEM() throws {
        let key = try makeTestKey()
        let parsed = try GooglePlayAuthService.rsaPrivateKey(fromPEM: key.pkcs8PEM)
        var error: Unmanaged<CFError>?
        let data = try #require(SecKeyCopyExternalRepresentation(parsed, &error) as Data?)
        #expect(data == key.pkcs1DER)
    }

    @Test func rejectsGarbagePEM() {
        #expect(throws: (any Error).self) {
            _ = try GooglePlayAuthService.rsaPrivateKey(fromPEM: "-----BEGIN PRIVATE KEY-----\nnot base64!!!\n-----END PRIVATE KEY-----")
        }
    }

    @Test func makeAssertionProducesVerifiableRS256JWT() throws {
        let key = try makeTestKey()
        let jwt = try GooglePlayAuthService.makeAssertion(account: account(pem: key.pkcs8PEM))

        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        #expect(parts.count == 3)

        // Header: RS256 / JWT / kid.
        let headerData = base64urlDecode(String(parts[0]))
        let header = try #require(try JSONSerialization.jsonObject(with: headerData) as? [String: String])
        #expect(header["alg"] == "RS256")
        #expect(header["typ"] == "JWT")
        #expect(header["kid"] == "kid-123")

        // Claims: iss / scope / aud.
        let claimsData = base64urlDecode(String(parts[1]))
        let claims = try #require(try JSONSerialization.jsonObject(with: claimsData) as? [String: Any])
        #expect(claims["iss"] as? String == "robot@demo.iam.gserviceaccount.com")
        #expect(claims["scope"] as? String == GooglePlayAuthService.scope)
        #expect(claims["aud"] as? String == "https://oauth2.googleapis.com/token")

        // Signature verifies against the public key over "header.claims".
        let signingInput = "\(parts[0]).\(parts[1])"
        let signature = base64urlDecode(String(parts[2]))
        var error: Unmanaged<CFError>?
        let verified = SecKeyVerifySignature(
            key.publicKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            Data(signingInput.utf8) as CFData,
            signature as CFData,
            &error
        )
        #expect(verified)
    }
}
#endif
