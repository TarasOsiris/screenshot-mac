import Foundation
import Observation

@Observable
final class AppStoreConnectCredentialsStore {
    static let shared = AppStoreConnectCredentialsStore()

    private static let issuerIdKey = "ascIssuerId"
    private static let keyIdKey = "ascKeyId"
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

    private(set) var hasPrivateKey: Bool

    private init() {
        self.issuerId = UserDefaults.standard.string(forKey: Self.issuerIdKey) ?? ""
        self.keyId = UserDefaults.standard.string(forKey: Self.keyIdKey) ?? ""
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
        isIssuerIdValid
            && isKeyIdValid
            && Self.normalizedPrivateKey(KeychainService.load(account: Self.keychainAccount)) != nil
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
        hasPrivateKey = Self.normalizedPrivateKey(KeychainService.load(account: Self.keychainAccount)) != nil
    }

    func privateKeyPEM() -> String? {
        let pem = Self.normalizedPrivateKey(KeychainService.load(account: Self.keychainAccount))
        hasPrivateKey = pem != nil
        return pem
    }

    private static func normalizedPrivateKey(_ pem: String?) -> String? {
        guard let pem else { return nil }
        let normalized = pem.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
