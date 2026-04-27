import Foundation
import Observation

@Observable
final class AppStoreConnectCredentialsStore {
    static let shared = AppStoreConnectCredentialsStore()

    private static let issuerIdKey = "ascIssuerId"
    private static let keyIdKey = "ascKeyId"
    private static let demoModeKey = "ascDemoMode"
    private static let keychainAccount = "default"

    var issuerId: String {
        didSet {
            guard issuerId != oldValue else { return }
            UserDefaults.standard.set(issuerId, forKey: Self.issuerIdKey)
        }
    }

    var keyId: String {
        didSet {
            guard keyId != oldValue else { return }
            UserDefaults.standard.set(keyId, forKey: Self.keyIdKey)
        }
    }

    /// When on, App Store Connect API calls are intercepted and returned with mock
    /// data so App Review (or anyone without an API key) can exercise the upload flow
    /// end-to-end without sending traffic to Apple's servers.
    var isDemoMode: Bool {
        didSet {
            guard isDemoMode != oldValue else { return }
            UserDefaults.standard.set(isDemoMode, forKey: Self.demoModeKey)
        }
    }

    private(set) var hasPrivateKey: Bool

    private init() {
        self.issuerId = UserDefaults.standard.string(forKey: Self.issuerIdKey) ?? ""
        self.keyId = UserDefaults.standard.string(forKey: Self.keyIdKey) ?? ""
        self.isDemoMode = UserDefaults.standard.bool(forKey: Self.demoModeKey)
        self.hasPrivateKey = Self.normalizedPrivateKey(KeychainService.load(account: Self.keychainAccount)) != nil
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
        try KeychainService.save(normalized ?? pem, account: Self.keychainAccount)
        hasPrivateKey = true
    }

    func deletePrivateKey() {
        KeychainService.delete(account: Self.keychainAccount)
        hasPrivateKey = false
    }

    func refreshPrivateKeyPresence() {
        let present = Self.normalizedPrivateKey(KeychainService.load(account: Self.keychainAccount)) != nil
        if hasPrivateKey != present { hasPrivateKey = present }
    }

    func privateKeyPEM() -> String? {
        let pem = Self.normalizedPrivateKey(KeychainService.load(account: Self.keychainAccount))
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
