import Foundation
import Observation

/// Holds the Google Play service-account credential (a JSON key) plus demo-mode flag.
/// The raw JSON is kept in the Keychain (separate account from the App Store Connect key);
/// the package name is stored per-project, not here.
@Observable
final class GooglePlayCredentialsStore {
    static let shared = GooglePlayCredentialsStore()

    private static let demoModeKey = "googlePlayDemoMode"

    private let defaults: UserDefaults
    private let secrets: any SecretStore
    private let keychainAccount: String

    /// Parsed `client_email` from the stored service account, shown for confirmation. nil when unset.
    private(set) var clientEmail: String?
    private(set) var hasServiceAccount: Bool

    var isDemoMode: Bool {
        didSet {
            guard isDemoMode != oldValue else { return }
            defaults.set(isDemoMode, forKey: Self.demoModeKey)
        }
    }

    /// Defaults to the shipping storage; tests pass an isolated suite and an in-memory
    /// `SecretStore` so they never touch the real login Keychain.
    init(
        defaults: UserDefaults = .standard,
        secrets: any SecretStore = KeychainSecretStore(),
        keychainAccount: String = "googleplay"
    ) {
        self.defaults = defaults
        self.secrets = secrets
        self.keychainAccount = keychainAccount
        self.isDemoMode = defaults.bool(forKey: Self.demoModeKey)
        let parsed = Self.parse(secrets.load(account: keychainAccount))
        self.hasServiceAccount = parsed != nil
        self.clientEmail = parsed?.clientEmail
    }

    var isConfigured: Bool {
        if isDemoMode { return true }
        return hasServiceAccount
    }

    /// Validates that the JSON has the fields we need, then stores the raw JSON.
    func saveServiceAccount(json: String) throws {
        guard let parsed = Self.parse(json) else {
            throw GooglePlayCredentialsError.invalidServiceAccount
        }
        try secrets.save(json, account: keychainAccount)
        hasServiceAccount = true
        clientEmail = parsed.clientEmail
    }

    func deleteServiceAccount() {
        secrets.delete(account: keychainAccount)
        hasServiceAccount = false
        clientEmail = nil
    }

    /// The raw service-account JSON, or nil when unset.
    func serviceAccountJSON() -> String? {
        let json = secrets.load(account: keychainAccount)
        let parsed = Self.parse(json)
        if hasServiceAccount != (parsed != nil) { hasServiceAccount = parsed != nil }
        return parsed == nil ? nil : json
    }

    struct ServiceAccount {
        let clientEmail: String
        let privateKeyPEM: String
        let privateKeyId: String?
        let tokenURI: String
    }

    /// The parsed credential ready for signing, or nil when unset/invalid.
    func parsedServiceAccount() -> ServiceAccount? {
        Self.parse(secrets.load(account: keychainAccount))
    }

    private static func parse(_ json: String?) -> ServiceAccount? {
        guard let json, !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clientEmail = (object["client_email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clientEmail.isEmpty,
              let privateKey = object["private_key"] as? String,
              privateKey.contains("PRIVATE KEY")
        else { return nil }

        let tokenURI = (object["token_uri"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ServiceAccount(
            clientEmail: clientEmail,
            privateKeyPEM: privateKey,
            privateKeyId: object["private_key_id"] as? String,
            tokenURI: (tokenURI?.isEmpty == false ? tokenURI! : "https://oauth2.googleapis.com/token")
        )
    }
}

enum GooglePlayCredentialsError: Error, LocalizedError {
    case invalidServiceAccount

    var errorDescription: String? {
        switch self {
        case .invalidServiceAccount:
            return String(localized: "This doesn't look like a Google service account key. Download the JSON key from the Google Cloud console (it must contain \"client_email\" and \"private_key\").")
        }
    }
}
