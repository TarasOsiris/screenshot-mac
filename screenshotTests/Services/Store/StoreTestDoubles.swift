#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation
@testable import Screenshot_Bro
import Testing

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
    var activeVariants: [ScreenshotVariant] = []
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

/// Stands in for the `insertEdit`/`deleteEdit` probe the package step runs, so the flow's
/// verified and rejected branches test without opening a real Play edit.
@MainActor
final class FakeGPPackageVerifier: GPPackageVerifying {
    var error: (any Error)?
    private(set) var callCount = 0
    private(set) var lastPackageName: String?

    func verifyPackage(packageName: String) async throws {
        callCount += 1
        lastPackageName = packageName
        if let error { throw error }
    }
}

/// An `ASCUploadDocument` backed by plain values. Sibling of `StubGPDocument`.
@MainActor
final class StubASCDocument: ASCUploadDocument {
    var rows: [ScreenshotRow]
    var activeVariants: [ScreenshotVariant] = []
    var activeProjectName: String
    var localeState: LocaleState
    var availableFontFamilySet: Set<String> = []
    var documentStamp: DocumentStamp?
    var savedASCAppId: String?

    init(
        rows: [ScreenshotRow] = [],
        projectName: String = "Fixture",
        localeState: LocaleState = .default,
        savedASCAppId: String? = nil
    ) {
        self.rows = rows
        self.activeProjectName = projectName
        self.localeState = localeState
        self.savedASCAppId = savedASCAppId
    }

    func rememberASCAppId(_ appId: String) { savedASCAppId = appId }

    func referencedImageFileNames(forRow row: ScreenshotRow, localeCode: String) -> Set<String> { [] }

    func loadFullResolutionImages(fileNames: Set<String>, cache: inout [String: NSImage]) -> [String: NSImage] { [:] }
}

/// The scripted `ASCUploadAPI` the protocol's doc comment promised and nobody had written. Every
/// method has an inert default, so growing the protocol only touches this file.
@MainActor
final class FakeASCUploadAPI: ASCUploadAPI {
    var appsWithVersions: [ASCAppWithVersions] = []
    var versionsByAppId: [String: [ASCAppStoreVersion]] = [:]
    var localizationsByVersionId: [String: [ASCAppStoreVersionLocalization]] = [:]
    var appInfosByAppId: [String: [ASCAppInfo]] = [:]
    var appInfoLocalizationsByAppInfoId: [String: [ASCAppInfoLocalization]] = [:]

    /// Popped in order; the last result repeats once exhausted.
    var createResults: [Result<ASCAppStoreVersionLocalization, Error>] = []
    private(set) var createCalls: [(versionId: String, locale: String, attributeKeys: Set<String>)] = []
    private(set) var createdAttributes: [[String: AnyEncodable]] = []

    func listAppsWithVersions(limit: Int) async throws -> [ASCAppWithVersions] { appsWithVersions }

    func listAppStoreVersions(appId: String, limit: Int) async throws -> [ASCAppStoreVersion] {
        versionsByAppId[appId] ?? []
    }

    func listLocalizations(versionId: String, limit: Int) async throws -> [ASCAppStoreVersionLocalization] {
        localizationsByVersionId[versionId] ?? []
    }

    func listAppInfos(appId: String) async throws -> [ASCAppInfo] { appInfosByAppId[appId] ?? [] }

    func listAppInfoLocalizations(appInfoId: String, limit: Int) async throws -> [ASCAppInfoLocalization] {
        appInfoLocalizationsByAppInfoId[appInfoId] ?? []
    }

    /// Popped in order; the last result repeats once exhausted.
    var createVersionResults: [Result<ASCAppStoreVersion, Error>] = []
    private(set) var createVersionCalls: [(appId: String, platform: ASCPlatform, versionString: String)] = []

    func createAppStoreVersion(
        appId: String,
        platform: ASCPlatform,
        versionString: String
    ) async throws -> ASCAppStoreVersion {
        createVersionCalls.append((appId, platform, versionString))
        let result = createVersionResults.count > 1 ? createVersionResults.removeFirst() : createVersionResults.first
        switch result {
        case .success(let version):
            return version
        case .failure(let error):
            throw error
        case nil:
            return ASCAppStoreVersion(
                id: "created-\(platform.rawValue)-\(versionString)",
                attributes: .init(
                    versionString: versionString,
                    appStoreState: "PREPARE_FOR_SUBMISSION",
                    platform: platform.rawValue
                )
            )
        }
    }

    func createVersionLocalization(
        versionId: String,
        locale: String,
        attributes: [String: AnyEncodable]
    ) async throws -> ASCAppStoreVersionLocalization {
        createCalls.append((versionId, locale, Set(attributes.keys)))
        createdAttributes.append(attributes)
        let result = createResults.count > 1 ? createResults.removeFirst() : createResults.first
        switch result {
        case .success(let localization):
            return localization
        case .failure(let error):
            throw error
        case nil:
            return ASCAppStoreVersionLocalization(id: "created-\(locale)", attributes: .init(locale: locale))
        }
    }

    func updateVersionLocalization(id: String, attributes: [String: AnyEncodable]) async throws {}

    func updateAppInfoLocalization(id: String, attributes: [String: AnyEncodable]) async throws {}

    func updateAppStoreVersion(id: String, attributes: [String: AnyEncodable]) async throws {}
}

/// A scripted `ASCExperimentAPI`: experiments and treatments are whatever the test seeds.
@MainActor
final class FakeASCExperimentAPI: ASCExperimentAPI {
    var experiments: [ASCExperiment] = []
    var treatmentsByExperiment: [String: [ASCExperimentTreatment]] = [:]

    func listExperiments(appId: String) async throws -> [ASCExperiment] { experiments }

    func experiment(id: String) async throws -> ASCExperiment {
        try #require(experiments.first { $0.id == id })
    }

    func createExperiment(appId: String, platform: ASCPlatform, name: String, trafficProportion: Int) async throws -> ASCExperiment {
        let experiment = ASCExperiment.fixture(id: "exp-new", name: name, platform: platform)
        experiments.append(experiment)
        return experiment
    }

    func startExperiment(id: String) async throws -> ASCExperiment {
        try await experiment(id: id)
    }

    func listTreatments(experimentId: String) async throws -> [ASCExperimentTreatment] {
        treatmentsByExperiment[experimentId] ?? []
    }

    func createTreatment(experimentId: String, name: String) async throws -> ASCExperimentTreatment {
        let treatment = ASCExperimentTreatment(id: "t-\(name)", attributes: .init(name: name))
        treatmentsByExperiment[experimentId, default: []].append(treatment)
        return treatment
    }

    func listTreatmentLocalizations(treatmentId: String) async throws -> [ASCTreatmentLocalization] { [] }

    func createTreatmentLocalization(treatmentId: String, locale: String) async throws -> ASCTreatmentLocalization {
        ASCTreatmentLocalization(id: "tl-\(treatmentId)-\(locale)", attributes: .init(locale: locale))
    }

    func submitExperimentForReview(appId: String, platform: ASCPlatform, experimentId: String) async throws {}
}

extension ASCExperiment {
    static func fixture(
        id: String,
        name: String = "Test",
        platform: ASCPlatform = .ios,
        state: ASCExperimentState = .prepareForSubmission
    ) -> ASCExperiment {
        ASCExperiment(
            id: id,
            attributes: .init(name: name, platform: platform.rawValue, state: state.rawValue, trafficProportion: 50)
        )
    }
}
