import Foundation
import CryptoKit

enum AppStoreConnectAuthError: Error, LocalizedError {
    case missingIssuerId
    case invalidIssuerId
    case missingKeyId
    case invalidKeyId
    case missingPrivateKey
    case invalidPrivateKey
    case signingFailed

    var errorDescription: String? {
        switch self {
        case .missingIssuerId:
            return String(localized: "Paste the Issuer ID from the API Keys page.")
        case .invalidIssuerId:
            return String(localized: "Issuer ID should be a UUID.")
        case .missingKeyId:
            return String(localized: "Paste the 10-character Key ID.")
        case .invalidKeyId:
            return String(localized: "Key ID is usually 10 uppercase letters and numbers.")
        case .missingPrivateKey:
            return String(localized: "Import the .p8 file downloaded when the key was created.")
        case .invalidPrivateKey:
            return String(localized: "Could not parse the private key. Make sure it's a valid .p8 file downloaded from App Store Connect.")
        case .signingFailed:
            return String(localized: "Failed to sign the JWT token.")
        }
    }
}

final class AppStoreConnectAuthService {
    static let shared = AppStoreConnectAuthService()

    private struct Snapshot: Equatable {
        let issuerId: String
        let keyId: String
        let pem: String
    }

    private struct CachedToken {
        let token: String
        let expiresAt: Date
        let snapshot: Snapshot
    }

    private var cachedToken: CachedToken?
    private var cachedKey: (pem: String, key: P256.Signing.PrivateKey)?

    private let credentials: AppStoreConnectCredentialsStore

    init(credentials: AppStoreConnectCredentialsStore = .shared) {
        self.credentials = credentials
    }

    func token() throws -> String {
        let snapshot = try currentSnapshot()
        if let cached = cachedToken,
           cached.snapshot == snapshot,
           cached.expiresAt.timeIntervalSinceNow > 60 {
            return cached.token
        }
        return try makeToken(snapshot: snapshot)
    }

    private func currentSnapshot() throws -> Snapshot {
        let issuer = credentials.trimmedIssuerId
        guard !issuer.isEmpty else { throw AppStoreConnectAuthError.missingIssuerId }
        guard UUID(uuidString: issuer) != nil else { throw AppStoreConnectAuthError.invalidIssuerId }

        let keyId = credentials.trimmedKeyId
        guard !keyId.isEmpty else { throw AppStoreConnectAuthError.missingKeyId }
        guard credentials.isKeyIdValid else { throw AppStoreConnectAuthError.invalidKeyId }

        guard let pem = credentials.privateKeyPEM() else {
            throw AppStoreConnectAuthError.missingPrivateKey
        }
        return Snapshot(issuerId: issuer, keyId: keyId, pem: pem)
    }

    private func privateKey(for pem: String) throws -> P256.Signing.PrivateKey {
        if let cachedKey, cachedKey.pem == pem { return cachedKey.key }
        do {
            let key = try P256.Signing.PrivateKey(pemRepresentation: pem)
            cachedKey = (pem, key)
            return key
        } catch {
            throw AppStoreConnectAuthError.invalidPrivateKey
        }
    }

    private func makeToken(snapshot: Snapshot) throws -> String {
        let privateKey = try privateKey(for: snapshot.pem)

        let header: [String: String] = ["alg": "ES256", "kid": snapshot.keyId, "typ": "JWT"]
        let iat = Int(Date().timeIntervalSince1970)
        let exp = iat + 1200 // 20 minutes — ASC maximum
        let claims: [String: Any] = [
            "iss": snapshot.issuerId,
            "iat": iat,
            "exp": exp,
            "aud": "appstoreconnect-v1"
        ]

        let headerJSON = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        let claimsJSON = try JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys])
        let signingInput = Self.base64URL(headerJSON) + "." + Self.base64URL(claimsJSON)

        let signature: P256.Signing.ECDSASignature
        do {
            signature = try privateKey.signature(for: Data(signingInput.utf8))
        } catch {
            throw AppStoreConnectAuthError.signingFailed
        }

        let token = signingInput + "." + Self.base64URL(signature.rawRepresentation)
        cachedToken = CachedToken(
            token: token,
            expiresAt: Date(timeIntervalSince1970: TimeInterval(exp)),
            snapshot: snapshot
        )
        return token
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
