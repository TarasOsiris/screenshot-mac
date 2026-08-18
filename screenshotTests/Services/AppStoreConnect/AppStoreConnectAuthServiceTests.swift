import CryptoKit
@testable import Screenshot_Bro
import Testing

// Each test builds its own credential store over an isolated UserDefaults suite and an in-memory
// secret store. Previously these ran against AppStoreConnectCredentialsStore.shared, which meant
// writing a real ES256 private key into the developer's login Keychain and restoring it via a
// hand-rolled snapshot — one missed `defer` away from leaving it behind. Nothing here is
// process-global any more, so the suite needs no `.serialized`.
struct AppStoreConnectAuthServiceTests {

    @Test func credentialsRequireValidIssuerAndKeyId() throws {
        let credentials = AppStoreConnectCredentialsStore.isolatedForTesting()
        credentials.isDemoMode = false
        credentials.issuerId = "not-a-uuid"
        credentials.keyId = "short"
        try credentials.savePrivateKey(P256.Signing.PrivateKey().pemRepresentation)

        #expect(credentials.isConfigured == false)
    }

    @Test func authServiceReportsMissingPrivateKey() {
        let credentials = AppStoreConnectCredentialsStore.isolatedForTesting()
        credentials.issuerId = "57246542-96fe-1a63-e053-0824d011072a"
        credentials.keyId = "ABC123DE45"
        credentials.deletePrivateKey()

        let auth = AppStoreConnectAuthService(credentials: credentials)

        #expect(throws: AppStoreConnectAuthError.missingPrivateKey) {
            _ = try auth.token()
        }
    }

    @Test func demoModeReportsConfiguredEvenWithoutCredentials() {
        let credentials = AppStoreConnectCredentialsStore.isolatedForTesting()
        credentials.issuerId = ""
        credentials.keyId = ""
        credentials.deletePrivateKey()
        credentials.isDemoMode = true

        #expect(credentials.isConfigured == true)
    }

    @Test func authServiceRejectsInvalidIssuerBeforeSigning() throws {
        let credentials = AppStoreConnectCredentialsStore.isolatedForTesting()
        credentials.issuerId = "bad-issuer"
        credentials.keyId = "ABC123DE45"
        try credentials.savePrivateKey(P256.Signing.PrivateKey().pemRepresentation)

        let auth = AppStoreConnectAuthService(credentials: credentials)

        #expect(throws: AppStoreConnectAuthError.invalidIssuerId) {
            _ = try auth.token()
        }
    }
}
