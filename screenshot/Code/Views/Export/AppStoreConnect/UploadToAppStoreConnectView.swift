#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

struct UploadToAppStoreConnectView: View {
    /// Declared first so the memberwise initializer reads `UploadToAppStoreConnectView(mode:)`.
    var mode: ASCFlowMode = .screenshots

    @Environment(\.dismiss) var dismiss
    @Environment(AppState.self) var state
    #if os(iOS)
    @Environment(AppNavigationRouter.self) var router
    #endif

    @State var step: ASCUploadStep = .pickingApp
    #if os(iOS)
    // iPad presents the wizard as a NavigationStack push-per-step flow; `path` holds the
    // pushed steps (root `.pickingApp` is implicit). `step` is kept in sync for the
    // terminal uploading/done screen, which flips its content on `step` rather than a push.
    @State var path: [ASCUploadStep] = []
    #endif
    @State var appsWithVersions: [ASCAppWithVersions] = []
    @State var selectedApp: ASCApp?
    @AppStorage("uploadHideNonUploadable") var hideNonUploadable: Bool = true

    @State var versions: [ASCAppStoreVersion] = []
    @State var selectedVersionIds: Set<String> = []

    @State var localizationsByVersionId: [String: [ASCAppStoreVersionLocalization]] = [:]

    @State var versionDrafts: [ASCVersionLocaleDraft] = []
    @State var appInfoDrafts: [ASCAppInfoLocaleDraft] = []
    @State var copyrightByVersion: [String: String] = [:]
    @State var originalCopyrightByVersion: [String: String] = [:]
    @State var selectedMetadataLocale: String?
    /// The version whose metadata the editing screen is currently showing (the active tab).
    @State var metadataVersionId: String?

    @State var destinationPlans: [ASCDestinationPlan] = []
    @State var isPreflightExpanded = true
    @State var expandedRowPlanIds: Set<String> = []   // absent = collapsed (default)
    @State var uploadProgress: UploadProgress?
    @State var uploadTask: Task<Void, Never>?
    @State var uploadSummary: ASCUploadSummary?
    @State var metadataSummary: ASCMetadataSaveSummary?
    @State var screenshotSync = ASCScreenshotSyncCoordinator()

    @State var errorMessage: String?
    /// Full error text (summary + API response + context). When nil, the Details button falls back to `errorMessage`.
    @State var errorDetailsText: String?
    @State var presentedErrorDetails: UploadFailureDetail?
    @State var displayTypeDetailsPlanId: String?
    @State var isBusy = false
    @State var isConfirmingUpload = false
    @State var isConfirmingReviewedSync = false
    @State var credentials = AppStoreConnectCredentialsStore.shared

    var apps: [ASCApp] { appsWithVersions.map(\.app) }

    var selectedVersions: [ASCAppStoreVersion] {
        versions.filter { selectedVersionIds.contains($0.id) }
    }

    var selectedVersion: ASCAppStoreVersion? {
        let selected = selectedVersions
        return selected.count == 1 ? selected.first : nil
    }

    /// The selected version whose metadata the editing screen is showing (the active tab).
    var activeMetadataVersion: ASCAppStoreVersion? {
        selectedVersions.first { $0.id == metadataVersionId } ?? selectedVersions.first
    }

    var body: some View {
        #if os(macOS)
        sharedModifiers(macBody)
        #else
        sharedModifiers(iosBody)
        #endif
    }

    /// `.task`, error-details sheet, and sync confirmation are identical on both platforms.
    private func sharedModifiers(_ content: some View) -> some View {
        content
            .task { await loadAppsIfNeeded() }
            .onDisappear {
                uploadTask?.cancel()
                screenshotSync.discard()
            }
            .sheet(item: $presentedErrorDetails) { details in
                UploadFailureDetailsSheet(details: details.message)
            }
            .confirmationDialog(
                isConfirmingReviewedSync
                    ? "Apply reviewed screenshot changes?"
                    : "Upload to App Store Connect",
                isPresented: $isConfirmingUpload,
                titleVisibility: .visible
            ) {
                Button(
                    isConfirmingReviewedSync ? "Apply Selected Changes" : "Upload",
                    role: .destructive
                ) {
                    if isConfirmingReviewedSync {
                        startReviewedScreenshotSync()
                    } else {
                        startDirectScreenshotSync()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(confirmationMessage)
            }
    }

    #if os(macOS)
    private var macBody: some View {
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
    }
    #endif

    // MARK: - Navigation (shared)

    /// Move forward one step. macOS swaps the single-screen state; iPad pushes onto the stack.
    func advance(to next: ASCUploadStep) {
        step = next
        #if os(iOS)
        path.append(next)
        #endif
    }

    /// Return to the originating plan/review after a sync error or cancellation.
    func retreatAfterScreenshotSync(to destination: ASCUploadStep) {
        step = destination
        #if os(iOS)
        if path.last == .uploading || path.last == .done {
            path.removeLast()
        }
        #endif
    }
}
