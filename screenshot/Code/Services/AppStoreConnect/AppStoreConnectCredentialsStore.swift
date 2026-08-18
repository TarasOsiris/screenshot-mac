import Foundation
import Observation

@Observable
final class AppStoreConnectCredentialsStore {
    static let shared = AppStoreConnectCredentialsStore()

    private static let issuerIdKey = "ascIssuerId"
    private static let keyIdKey = "ascKeyId"
    private static let demoModeKey = "ascDemoMode"

    private let defaults: UserDefaults
    private let secrets: any SecretStore
    private let keychainAccount: String

    var issuerId: String {
        didSet {
            guard issuerId != oldValue else { return }
            defaults.set(issuerId, forKey: Self.issuerIdKey)
        }
    }

    var keyId: String {
        didSet {
            guard keyId != oldValue else { return }
            defaults.set(keyId, forKey: Self.keyIdKey)
        }
    }

    /// When on, App Store Connect API calls are intercepted and returned with mock
    /// data so App Review (or anyone without an API key) can exercise the upload flow
    /// end-to-end without sending traffic to Apple's servers.
    var isDemoMode: Bool {
        didSet {
            guard isDemoMode != oldValue else { return }
            defaults.set(isDemoMode, forKey: Self.demoModeKey)
        }
    }

    private(set) var hasPrivateKey: Bool

    /// Defaults to the shipping storage. Tests pass an isolated `UserDefaults` suite and an
    /// in-memory `SecretStore` so they never touch the real login Keychain.
    init(
        defaults: UserDefaults = .standard,
        secrets: any SecretStore = KeychainSecretStore(),
        keychainAccount: String = "default"
    ) {
        self.defaults = defaults
        self.secrets = secrets
        self.keychainAccount = keychainAccount
        self.issuerId = defaults.string(forKey: Self.issuerIdKey) ?? ""
        self.keyId = defaults.string(forKey: Self.keyIdKey) ?? ""
        self.isDemoMode = defaults.bool(forKey: Self.demoModeKey)
        self.hasPrivateKey = Self.normalizedPrivateKey(secrets.load(account: keychainAccount)) != nil
    }

    var trimmedIssuerId: String {
        issuerId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedKeyId: String {
        keyId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isIssuerIdValid: Bool {
        UUID(uuidString: trimmedIssuerId) != nil
    }

    var isKeyIdValid: Bool {
        trimmedKeyId.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil
    }

    var isConfigured: Bool {
        if isDemoMode { return true }
        return isIssuerIdValid && isKeyIdValid && hasPrivateKey
    }

    func savePrivateKey(_ pem: String) throws {
        let normalized = Self.normalizedPrivateKey(pem)
        try secrets.save(normalized ?? pem, account: keychainAccount)
        hasPrivateKey = true
    }

    func deletePrivateKey() {
        secrets.delete(account: keychainAccount)
        hasPrivateKey = false
    }

    func refreshPrivateKeyPresence() {
        let present = Self.normalizedPrivateKey(secrets.load(account: keychainAccount)) != nil
        if hasPrivateKey != present { hasPrivateKey = present }
    }

    func privateKeyPEM() -> String? {
        let pem = Self.normalizedPrivateKey(secrets.load(account: keychainAccount))
        let present = pem != nil
        if hasPrivateKey != present { hasPrivateKey = present }
        return pem
    }

    private static func normalizedPrivateKey(_ pem: String?) -> String? {
        guard let pem else { return nil }
        let normalized = pem.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
