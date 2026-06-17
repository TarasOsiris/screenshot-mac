#if DEBUG
import Foundation
import Security

enum GooglePlayAuthError: Error, LocalizedError {
    case missingServiceAccount
    case invalidPrivateKey
    case signingFailed
    case tokenRequestFailed(status: Int, message: String)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .missingServiceAccount:
            return String(localized: "Import the Google service account JSON key in Settings → Google Play.")
        case .invalidPrivateKey:
            return String(localized: "Could not read the private key from the service account JSON. Re-download the key from the Google Cloud console.")
        case .signingFailed:
            return String(localized: "Failed to sign the authentication token.")
        case .tokenRequestFailed(let status, let message):
            return String(localized: "Google rejected the sign-in (\(status)): \(message)")
        case .transport(let error):
            return error.localizedDescription
        }
    }
}

/// Exchanges a Google service-account JSON key for an OAuth2 access token scoped to
/// the Android Publisher API. Unlike App Store Connect (ES256 JWT used directly as the
/// bearer), Google requires an RS256-signed JWT exchanged at the token endpoint for a
/// short-lived access token, which is then sent as the bearer.
final class GooglePlayAuthService {
    static let shared = GooglePlayAuthService()

    static let scope = "https://www.googleapis.com/auth/androidpublisher"

    private struct CachedToken {
        let token: String
        let expiresAt: Date
        let clientEmail: String
    }

    private var cachedToken: CachedToken?
    private let credentials: GooglePlayCredentialsStore
    private let session: URLSession

    init(credentials: GooglePlayCredentialsStore = .shared, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    func token() async throws -> String {
        guard let account = credentials.parsedServiceAccount() else {
            throw GooglePlayAuthError.missingServiceAccount
        }
        if let cached = cachedToken,
           cached.clientEmail == account.clientEmail,
           cached.expiresAt.timeIntervalSinceNow > 60 {
            return cached.token
        }

        let assertion = try Self.makeAssertion(account: account)
        let (token, expiresIn) = try await requestAccessToken(assertion: assertion, tokenURI: account.tokenURI)
        cachedToken = CachedToken(
            token: token,
            expiresAt: Date(timeIntervalSinceNow: TimeInterval(expiresIn)),
            clientEmail: account.clientEmail
        )
        return token
    }

    // MARK: - JWT

    static func makeAssertion(account: GooglePlayCredentialsStore.ServiceAccount) throws -> String {
        var header: [String: String] = ["alg": "RS256", "typ": "JWT"]
        if let kid = account.privateKeyId, !kid.isEmpty { header["kid"] = kid }

        let iat = Int(Date().timeIntervalSince1970)
        let claims: [String: Any] = [
            "iss": account.clientEmail,
            "scope": scope,
            "aud": account.tokenURI,
            "iat": iat,
            "exp": iat + 3600
        ]

        let headerJSON = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        let claimsJSON = try JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys])
        let signingInput = base64URL(headerJSON) + "." + base64URL(claimsJSON)

        let key = try rsaPrivateKey(fromPEM: account.privateKeyPEM)
        let signature = try sign(Data(signingInput.utf8), with: key)
        return signingInput + "." + base64URL(signature)
    }

    private func requestAccessToken(assertion: String, tokenURI: String) async throws -> (token: String, expiresIn: Int) {
        guard let url = URL(string: tokenURI) else {
            throw GooglePlayAuthError.tokenRequestFailed(status: -1, message: "Invalid token URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=\(assertion)"
        request.httpBody = body.data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GooglePlayAuthError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw GooglePlayAuthError.tokenRequestFailed(status: -1, message: "Non-HTTP response")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(http.statusCode) else {
            let message = (json?["error_description"] as? String)
                ?? (json?["error"] as? String)
                ?? "HTTP \(http.statusCode)"
            throw GooglePlayAuthError.tokenRequestFailed(status: http.statusCode, message: message)
        }
        guard let token = json?["access_token"] as? String else {
            throw GooglePlayAuthError.tokenRequestFailed(status: http.statusCode, message: "Missing access_token in response")
        }
        let expiresIn = (json?["expires_in"] as? Int) ?? 3600
        return (token, expiresIn)
    }

    // MARK: - RSA (Security framework — CryptoKit has no RSA)

    static func rsaPrivateKey(fromPEM pem: String) throws -> SecKey {
        guard let der = pemToDER(pem) else { throw GooglePlayAuthError.invalidPrivateKey }
        // Google ships PKCS#8 ("BEGIN PRIVATE KEY"); SecKeyCreateWithData wants the inner PKCS#1 key.
        let pkcs1 = pem.contains("RSA PRIVATE KEY") ? der : (pkcs1FromPKCS8(der) ?? der)

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, &error) else {
            throw GooglePlayAuthError.invalidPrivateKey
        }
        return key
    }

    private static func sign(_ data: Data, with key: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            &error
        ) else {
            throw GooglePlayAuthError.signingFailed
        }
        return signature as Data
    }

    private static func pemToDER(_ pem: String) -> Data? {
        let base64 = pem
            .components(separatedBy: "\n")
            .filter { !$0.hasPrefix("-----") }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Data(base64Encoded: base64)
    }

    /// Unwraps a PKCS#8 PrivateKeyInfo to the inner PKCS#1 RSAPrivateKey by walking the
    /// DER: SEQUENCE { INTEGER version, SEQUENCE algorithm, OCTET STRING privateKey }.
    static func pkcs1FromPKCS8(_ der: Data) -> Data? {
        var parser = DERParser(der)
        guard parser.readSequenceHeader() else { return nil }
        guard parser.skipElement() else { return nil }            // version INTEGER
        guard parser.skipElement() else { return nil }            // algorithm SEQUENCE
        return parser.readOctetString()                            // privateKey OCTET STRING
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Minimal DER reader — just enough to unwrap a PKCS#8 RSA key.
private struct DERParser {
    private let bytes: [UInt8]
    private var index = 0

    init(_ data: Data) { self.bytes = [UInt8](data) }

    private mutating func readByte() -> UInt8? {
        guard index < bytes.count else { return nil }
        defer { index += 1 }
        return bytes[index]
    }

    private mutating func readLength() -> Int? {
        guard let first = readByte() else { return nil }
        if first & 0x80 == 0 { return Int(first) }
        let count = Int(first & 0x7F)
        guard count > 0, count <= 4 else { return nil }
        var length = 0
        for _ in 0..<count {
            guard let byte = readByte() else { return nil }
            length = (length << 8) | Int(byte)
        }
        return length
    }

    mutating func readSequenceHeader() -> Bool {
        guard readByte() == 0x30, readLength() != nil else { return false }
        return true
    }

    /// Skips a TLV element (tag + length + value).
    mutating func skipElement() -> Bool {
        guard readByte() != nil, let length = readLength() else { return false }
        guard index + length <= bytes.count else { return false }
        index += length
        return true
    }

    mutating func readOctetString() -> Data? {
        guard readByte() == 0x04, let length = readLength() else { return nil }
        guard index + length <= bytes.count else { return nil }
        let slice = bytes[index..<index + length]
        index += length
        return Data(slice)
    }
}
#endif
