#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation
@testable import Screenshot_Bro

/// A `SecretStore` backed by a dictionary. Tests that exercise credential storage used to write
/// a real ES256 private key into the developer's login Keychain and restore it by hand; they
/// take one of these instead.
@MainActor
final class InMemorySecretStore: SecretStore {
    private var values: [String: String] = [:]

    init(_ values: [String: String] = [:]) { self.values = values }

    func load(account: String) -> String? { values[account] }
    func save(_ value: String, account: String) throws { values[account] = value }
    func delete(account: String) { values.removeValue(forKey: account) }
}

/// A `UserDefaults` suite nobody else writes to, so a test can't observe or clobber the app's
/// real preferences. The caller keeps it for the length of the test; the suite is removed on
/// deinit.
@MainActor
func makeIsolatedDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
    // A fresh suite name per call means no cleanup ordering to get wrong.
    UserDefaults(suiteName: "test.\(name)") ?? .standard
}

@MainActor
extension AppStoreConnectCredentialsStore {
    /// An ASC credential store wired to throwaway storage.
    static func isolatedForTesting(
        secrets: InMemorySecretStore = InMemorySecretStore()
    ) -> AppStoreConnectCredentialsStore {
        AppStoreConnectCredentialsStore(
            defaults: makeIsolatedDefaults(),
            secrets: secrets,
            keychainAccount: "test-asc"
        )
    }
}

@MainActor
extension GooglePlayCredentialsStore {
    /// A Google Play credential store wired to throwaway storage.
    static func isolatedForTesting(
        secrets: InMemorySecretStore = InMemorySecretStore()
    ) -> GooglePlayCredentialsStore {
        GooglePlayCredentialsStore(
            defaults: makeIsolatedDefaults(),
            secrets: secrets,
            keychainAccount: "test-googleplay"
        )
    }
}

/// A `GPUploadDocument` with no `AppState` behind it.
@MainActor
final class StubGPDocument: GPUploadDocument {
    var rows: [ScreenshotRow]
    var activeProjectName: String
    var localeState: LocaleState
    var availableFontFamilySet: Set<String> = []
    var documentStamp: DocumentStamp?
    var savedGooglePlayPackageName: String?
    /// Every value the flow asked to persist, so a test can assert demo mode never writes one.
    private(set) var rememberedPackageNames: [String?] = []

    init(
        rows: [ScreenshotRow] = [],
        projectName: String = "Fixture",
        localeState: LocaleState = .default,
        savedGooglePlayPackageName: String? = nil
    ) {
        self.rows = rows
        self.activeProjectName = projectName
        self.localeState = localeState
        self.savedGooglePlayPackageName = savedGooglePlayPackageName
    }

    func rememberGooglePlayPackageName(_ packageName: String?) {
        rememberedPackageNames.append(packageName)
        savedGooglePlayPackageName = packageName
    }

    func referencedImageFileNames(forRow row: ScreenshotRow, localeCode: String) -> Set<String> { [] }

    func loadFullResolutionImages(fileNames: Set<String>, cache: inout [String: NSImage]) -> [String: NSImage] { [:] }
}

/// A scriptable stand-in for `GooglePlayUploadService`.
@MainActor
final class FakeGPUploader: GPUploadPerforming {
    enum Outcome {
        case success(sentForReview: Bool)
        case cancelled
        case failure(any Error)
    }

    var outcome: Outcome = .success(sentForReview: false)
    private(set) var callCount = 0
    private(set) var lastPackageName: String?
    private(set) var lastSendForReview: Bool?

    @discardableResult
    func upload(
        packageName: String,
        targets: [GPUploadTarget],
        sendForReview: Bool,
        rows: [ScreenshotRow],
        source: any RowRenderSource,
        progress: @escaping (UploadProgress) -> Void
    ) async throws -> Bool {
        callCount += 1
        lastPackageName = packageName
        lastSendForReview = sendForReview
        switch outcome {
        case .success(let sent): return sent
        case .cancelled: throw CancellationError()
        case .failure(let error): throw error
        }
    }
}
