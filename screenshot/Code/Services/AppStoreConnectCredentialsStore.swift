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
        self.hasPrivateKey = KeychainService.load(account: Self.keychainAccount) != nil
    }

    var isConfigured: Bool {
        !issuerId.trimmingCharacters(in: .whitespaces).isEmpty
            && !keyId.trimmingCharacters(in: .whitespaces).isEmpty
            && hasPrivateKey
    }

    func savePrivateKey(_ pem: String) throws {
        try KeychainService.save(pem, account: Self.keychainAccount)
        hasPrivateKey = true
    }

    func deletePrivateKey() {
        KeychainService.delete(account: Self.keychainAccount)
        hasPrivateKey = false
    }

    func privateKeyPEM() -> String? {
        KeychainService.load(account: Self.keychainAccount)
    }
}
