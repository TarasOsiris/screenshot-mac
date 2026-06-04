// WHOLE_FILE_MACOS_GUARD
#if os(macOS)
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI


struct UploadToAppStoreConnectView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(AppState.self) var state

    @State var step: Step = .pickingApp
    @State var appsWithVersions: [ASCAppWithVersions] = []
    @State var selectedApp: ASCApp?
    @AppStorage("uploadHideNonUploadable") var hideNonUploadable: Bool = true

    @State var versions: [ASCAppStoreVersion] = []
    @State var selectedVersion: ASCAppStoreVersion?

    @State var localizations: [ASCAppStoreVersionLocalization] = []

    @State var versionDrafts: [VersionLocaleDraft] = []
    @State var appInfoDrafts: [AppInfoLocaleDraft] = []
    @State var copyrightDraft: String = ""
    @State var originalCopyright: String = ""
    @State var selectedMetadataLocale: String?

    @State var rowPlans: [RowPlan] = []
    @State var uploadProgress: ASCUploadProgress?
    @State var uploadTask: Task<Void, Never>?
    @State var uploadSummary: UploadSummary?

    @State var errorMessage: String?
    /// Full error text (summary + API response + context). When nil, the Details button falls back to `errorMessage`.
    @State var errorDetailsText: String?
    @State var presentedErrorDetails: ASCUploadFailureDetailItem?
    @State var displayTypeDetailsPlanId: UUID?
    @State var isBusy = false
    @State var isConfirmingUpload = false
    @State var credentials = AppStoreConnectCredentialsStore.shared

    struct UploadSummary {
        let appId: String?
        let appName: String
        let totalScreenshots: Int
        let localizationCount: Int
    }

    enum Step {
        case pickingApp
        case pickingVersion
        case editingMetadata
        case configuringPlan
        case uploading
        case done
    }

    struct VersionLocaleDraft: Identifiable {
        let id: String
        let locale: String
        var description: String
        var keywords: String
        var promotionalText: String
        var whatsNew: String
        var marketingUrl: String
        var supportUrl: String
        var original: ASCAppStoreVersionLocalization.Attributes

        var isChanged: Bool {
            description != (original.description ?? "")
                || keywords != (original.keywords ?? "")
                || promotionalText != (original.promotionalText ?? "")
                || whatsNew != (original.whatsNew ?? "")
                || marketingUrl != (original.marketingUrl ?? "")
                || supportUrl != (original.supportUrl ?? "")
        }

        func changedAttributes() -> [String: AnyEncodable] {
            var changes: [String: AnyEncodable] = [:]
            if description != (original.description ?? "") { changes["description"] = AnyEncodable(description) }
            if keywords != (original.keywords ?? "") { changes["keywords"] = AnyEncodable(keywords) }
            if promotionalText != (original.promotionalText ?? "") { changes["promotionalText"] = AnyEncodable(promotionalText) }
            if whatsNew != (original.whatsNew ?? "") { changes["whatsNew"] = AnyEncodable(whatsNew) }
            if marketingUrl != (original.marketingUrl ?? "") { changes["marketingUrl"] = AnyEncodable(marketingUrl) }
            if supportUrl != (original.supportUrl ?? "") { changes["supportUrl"] = AnyEncodable(supportUrl) }
            return changes
        }

        mutating func markSaved() {
            original = ASCAppStoreVersionLocalization.Attributes(
                locale: locale,
                description: description,
                keywords: keywords,
                promotionalText: promotionalText,
                whatsNew: whatsNew,
                marketingUrl: marketingUrl,
                supportUrl: supportUrl
            )
        }
    }

    struct AppInfoLocaleDraft: Identifiable {
        let id: String
        let locale: String
        var name: String
        var subtitle: String
        var privacyPolicyUrl: String
        var original: ASCAppInfoLocalization.Attributes

        var isChanged: Bool {
            name != (original.name ?? "")
                || subtitle != (original.subtitle ?? "")
                || privacyPolicyUrl != (original.privacyPolicyUrl ?? "")
        }

        func changedAttributes() -> [String: AnyEncodable] {
            var changes: [String: AnyEncodable] = [:]
            if name != (original.name ?? "") { changes["name"] = AnyEncodable(name) }
            if subtitle != (original.subtitle ?? "") { changes["subtitle"] = AnyEncodable(subtitle) }
            if privacyPolicyUrl != (original.privacyPolicyUrl ?? "") { changes["privacyPolicyUrl"] = AnyEncodable(privacyPolicyUrl) }
            return changes
        }

        mutating func markSaved() {
            original = ASCAppInfoLocalization.Attributes(
                locale: locale,
                name: name,
                subtitle: subtitle,
                privacyPolicyUrl: privacyPolicyUrl,
                privacyPolicyText: original.privacyPolicyText,
                privacyChoicesUrl: original.privacyChoicesUrl
            )
        }
    }

    struct RowPlan: Identifiable {
        let id: UUID
        var rowLabel: String
        var rowSize: CGSize
        var templateCount: Int
        var isEnabled: Bool
        var detectedDisplayType: ASCDisplayType?
        var selectedDisplayType: ASCDisplayType?
        var localeTargets: [LocaleTarget]
    }

    struct LocaleTarget: Identifiable {
        let id = UUID()
        var appLocaleCode: String
        var appLocaleLabel: String
        var selectedASCLocalizationId: String?
        var candidates: [ASCAppStoreVersionLocalization]
        var isEnabled: Bool
    }

    struct UploadPlanEntry: Identifiable {
        let id: String
        let rowLabel: String
        let sourceSizeLabel: String
        let displayTypeLabel: String
        let displayTypeRawValue: String
        let projectLocaleLabel: String
        let projectLocaleCode: String
        let appStoreLocaleCode: String?
        let templateCount: Int
        let isSelected: Bool
        let skipReason: String?

        var screenshotCount: Int { isSelected ? templateCount : 0 }
    }

    struct UploadLocaleGroup: Identifiable {
        let id: String
        let label: String
        let entries: [UploadPlanEntry]

        var screenshotCount: Int { entries.reduce(0) { $0 + $1.screenshotCount } }
    }

    var apps: [ASCApp] { appsWithVersions.map(\.app) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if credentials.isDemoMode {
                demoModeBanner
            }
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 860, height: 680)
        .task { await loadAppsIfNeeded() }
        .sheet(item: $presentedErrorDetails) { details in
            ASCUploadFailureDetailsSheet(details: details.message)
        }
        .confirmationDialog(
            "Replace existing screenshots?",
            isPresented: $isConfirmingUpload,
            titleVisibility: .visible
        ) {
            Button("Upload and Replace", role: .destructive) {
                Task { await startUpload() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
    }
}

#endif
