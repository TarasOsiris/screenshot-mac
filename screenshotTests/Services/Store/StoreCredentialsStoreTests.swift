import CryptoKit
import Foundation
@testable import Screenshot_Bro
import Testing

// Both credential stores gained an injectable init in the same change that made these tests
// possible: before it they had `private init()` and could only be exercised through `.shared`,
// i.e. against the real Keychain and the real UserDefaults.
struct StoreCredentialsStoreTests {

    // MARK: - App Store Connect

    @Test func ascRejectsMalformedIssuerAndKeyId() {
        let credentials = AppStoreConnectCredentialsStore.isolatedForTesting()

        credentials.issuerId = "not-a-uuid"
        #expect(credentials.isIssuerIdValid == false)
        credentials.issuerId = "57246542-96fe-1a63-e053-0824d011072a"
        #expect(credentials.isIssuerIdValid)

        // Key IDs are exactly ten uppercase alphanumerics.
        for bad in ["short", "abc123de45", "ABC123DE4", "ABC123DE456"] {
            credentials.keyId = bad
            #expect(credentials.isKeyIdValid == false, "\(bad) should be rejected")
        }
        credentials.keyId = "ABC123DE45"
        #expect(credentials.isKeyIdValid)
    }

    @Test func ascIsConfiguredNeedsAllThreePieces() throws {
        let credentials = AppStoreConnectCredentialsStore.isolatedForTesting()
        credentials.issuerId = "57246542-96fe-1a63-e053-0824d011072a"
        credentials.keyId = "ABC123DE45"
        #expect(credentials.isConfigured == false, "no private key yet")

        try credentials.savePrivateKey(P256.Signing.PrivateKey().pemRepresentation)
        #expect(credentials.isConfigured)

        credentials.deletePrivateKey()
        #expect(credentials.isConfigured == false)
    }

    /// Demo mode is what lets App Review exercise the upload flow with no API key at all, so it
    /// has to override the credential checks rather than sit alongside them.
    @Test func ascDemoModeOverridesEverything() {
        let credentials = AppStoreConnectCredentialsStore.isolatedForTesting()
        credentials.issuerId = ""
        credentials.keyId = ""
        credentials.isDemoMode = true
        #expect(credentials.isConfigured)
    }

    /// A key that is only whitespace must not read as present, or `isConfigured` says yes and
    /// signing then fails at upload time.
    @Test func ascBlankPrivateKeyIsNotAKey() throws {
        let secrets = InMemorySecretStore()
        let credentials = AppStoreConnectCredentialsStore.isolatedForTesting(secrets: secrets)
        try credentials.savePrivateKey("   \n  ")
        credentials.refreshPrivateKeyPresence()
        #expect(credentials.privateKeyPEM() == nil)
        #expect(credentials.hasPrivateKey == false)
    }

    @Test func ascPrivateKeyRoundTripsThroughTheSecretStore() throws {
        let credentials = AppStoreConnectCredentialsStore.isolatedForTesting()
        let pem = P256.Signing.PrivateKey().pemRepresentation
        try credentials.savePrivateKey(pem)
        #expect(credentials.privateKeyPEM() == pem.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Google Play

    @Test func googlePlayAcceptsAServiceAccountAndExposesItsEmail() throws {
        let credentials = GooglePlayCredentialsStore.isolatedForTesting()
        try credentials.saveServiceAccount(json: Self.serviceAccountJSON)

        #expect(credentials.hasServiceAccount)
        #expect(credentials.clientEmail == "robot@example.iam.gserviceaccount.com")
        #expect(credentials.isConfigured)

        let parsed = try #require(credentials.parsedServiceAccount())
        #expect(parsed.privateKeyPEM.contains("PRIVATE KEY"))
        #expect(parsed.privateKeyId == "abc123")
        #expect(parsed.tokenURI == "https://oauth2.googleapis.com/token")
    }

    /// `token_uri` is optional in the key file; the default must be filled in or signing posts
    /// to an empty URL.
    @Test func googlePlayDefaultsTheTokenURIWhenAbsent() throws {
        let credentials = GooglePlayCredentialsStore.isolatedForTesting()
        try credentials.saveServiceAccount(json: """
        {"client_email": "a@b.iam.gserviceaccount.com", "private_key": "-----BEGIN PRIVATE KEY-----\\nx\\n-----END PRIVATE KEY-----"}
        """)
        let parsed = try #require(credentials.parsedServiceAccount())
        #expect(parsed.tokenURI == "https://oauth2.googleapis.com/token")
    }

    @Test func googlePlayRejectsJSONMissingTheFieldsItNeeds() {
        let credentials = GooglePlayCredentialsStore.isolatedForTesting()
        for bad in [
            "not json at all",
            #"{"client_email": "a@b.com"}"#,                              // no private_key
            #"{"private_key": "-----BEGIN PRIVATE KEY-----"}"#,           // no client_email
            #"{"client_email": "", "private_key": "-----BEGIN PRIVATE KEY-----"}"#,
            #"{"client_email": "a@b.com", "private_key": "just a string"}"#,
        ] {
            #expect(throws: GooglePlayCredentialsError.invalidServiceAccount) {
                try credentials.saveServiceAccount(json: bad)
            }
        }
        #expect(credentials.hasServiceAccount == false)
    }

    @Test func googlePlayDeleteClearsBothFlagAndEmail() throws {
        let credentials = GooglePlayCredentialsStore.isolatedForTesting()
        try credentials.saveServiceAccount(json: Self.serviceAccountJSON)
        credentials.deleteServiceAccount()

        #expect(credentials.hasServiceAccount == false)
        #expect(credentials.clientEmail == nil)
        #expect(credentials.serviceAccountJSON() == nil)
        #expect(credentials.isConfigured == false)
    }

    @Test func googlePlayDemoModeOverridesEverything() {
        let credentials = GooglePlayCredentialsStore.isolatedForTesting()
        credentials.isDemoMode = true
        #expect(credentials.isConfigured)
    }

    private static let serviceAccountJSON = """
    {
      "client_email": "robot@example.iam.gserviceaccount.com",
      "private_key": "-----BEGIN PRIVATE KEY-----\\nMIIB\\n-----END PRIVATE KEY-----\\n",
      "private_key_id": "abc123",
      "token_uri": "https://oauth2.googleapis.com/token"
    }
    """
}
