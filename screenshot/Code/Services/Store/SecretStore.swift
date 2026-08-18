import Foundation

/// Where a store credential's secret half lives. Exists so the credential stores can be
/// constructed with an in-memory implementation under test: they previously reached
/// `KeychainService` statically, which meant `AppStoreConnectAuthServiceTests` wrote a real
/// ES256 private key into the developer's login Keychain and restored it by hand.
/// `@MainActor` to match `KeychainService` and both credential stores, which are already
/// main-actor isolated — this seam is about testability, not about moving Keychain access
/// off the main thread.
@MainActor
protocol SecretStore {
    func load(account: String) -> String?
    func save(_ value: String, account: String) throws
    func delete(account: String)
}

/// The shipping implementation: the login Keychain, via `KeychainService`.
@MainActor
struct KeychainSecretStore: SecretStore {
    func load(account: String) -> String? { KeychainService.load(account: account) }
    func save(_ value: String, account: String) throws { try KeychainService.save(value, account: account) }
    func delete(account: String) { KeychainService.delete(account: account) }
}
