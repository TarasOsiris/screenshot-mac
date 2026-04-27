import CryptoKit
import Testing
@testable import Screenshot_Bro

@Suite(.serialized)
struct AppStoreConnectAuthServiceTests {
    @Test func credentialsRequireValidIssuerAndKeyId() throws {
        let credentials = AppStoreConnectCredentialsStore.shared
        let snapshot = CredentialsSnapshot.capture(from: credentials)
        defer { snapshot.restore(into: credentials) }

        credentials.isDemoMode = false
        credentials.issuerId = "not-a-uuid"
        credentials.keyId = "short"
        try credentials.savePrivateKey(P256.Signing.PrivateKey().pemRepresentation)

        #expect(credentials.isConfigured == false)
    }

    @Test func authServiceReportsMissingPrivateKey() {
        let credentials = AppStoreConnectCredentialsStore.shared
        let snapshot = CredentialsSnapshot.capture(from: credentials)
        defer { snapshot.restore(into: credentials) }

        credentials.issuerId = "57246542-96fe-1a63-e053-0824d011072a"
        credentials.keyId = "ABC123DE45"
        credentials.deletePrivateKey()

        let auth = AppStoreConnectAuthService(credentials: credentials)

        #expect(throws: AppStoreConnectAuthError.missingPrivateKey) {
            _ = try auth.token()
        }
    }

    @Test func demoModeReportsConfiguredEvenWithoutCredentials() {
        let credentials = AppStoreConnectCredentialsStore.shared
        let snapshot = CredentialsSnapshot.capture(from: credentials)
        defer { snapshot.restore(into: credentials) }

        credentials.issuerId = ""
        credentials.keyId = ""
        credentials.deletePrivateKey()
        credentials.isDemoMode = true

        #expect(credentials.isConfigured == true)
    }

    @Test func authServiceRejectsInvalidIssuerBeforeSigning() throws {
        let credentials = AppStoreConnectCredentialsStore.shared
        let snapshot = CredentialsSnapshot.capture(from: credentials)
        defer { snapshot.restore(into: credentials) }

        credentials.issuerId = "bad-issuer"
        credentials.keyId = "ABC123DE45"
        try credentials.savePrivateKey(P256.Signing.PrivateKey().pemRepresentation)

        let auth = AppStoreConnectAuthService(credentials: credentials)

        #expect(throws: AppStoreConnectAuthError.invalidIssuerId) {
            _ = try auth.token()
        }
    }
}

private struct CredentialsSnapshot {
    let issuerId: String
    let keyId: String
    let isDemoMode: Bool
    let privateKeyPEM: String?

    static func capture(from credentials: AppStoreConnectCredentialsStore) -> CredentialsSnapshot {
        CredentialsSnapshot(
            issuerId: credentials.issuerId,
            keyId: credentials.keyId,
            isDemoMode: credentials.isDemoMode,
            privateKeyPEM: credentials.privateKeyPEM()
        )
    }

    func restore(into credentials: AppStoreConnectCredentialsStore) {
        credentials.issuerId = issuerId
        credentials.keyId = keyId
        credentials.isDemoMode = isDemoMode
        if let privateKeyPEM {
            try? credentials.savePrivateKey(privateKeyPEM)
        } else {
            credentials.deletePrivateKey()
        }
    }
}
