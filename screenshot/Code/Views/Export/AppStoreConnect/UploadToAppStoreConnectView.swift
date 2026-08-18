#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

struct UploadToAppStoreConnectView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(AppState.self) var state
    #if os(iOS)
    @Environment(AppNavigationRouter.self) var router
    #endif

    /// Everything about the flow — steps, fetched apps and versions, metadata drafts, the upload
    /// plan, progress and errors — lives here. See ASCUploadFlowModel.
    @State var model: ASCUploadFlowModel

    #if os(iOS)
    // iPad presents the wizard as a NavigationStack push-per-step flow; `path` holds the
    // pushed steps (root `.pickingApp` is implicit). The model's `step` is kept in sync for the
    // terminal uploading/done screen, which flips its content on `step` rather than a push.
    @State var path: [ASCUploadStep] = []
    #endif

    // View-local presentation state: disclosure, sheet and confirmation-dialog flags with no
    // flow meaning, plus the one preference an @Observable class can't host.
    @AppStorage("uploadHideNonUploadable") var hideNonUploadable: Bool = true
    @State var isPreflightExpanded = true
    @State var expandedRowPlanIds: Set<String> = []   // absent = collapsed (default)
    @State var presentedErrorDetails: UploadFailureDetail?
    @State var displayTypeDetailsPlanId: String?
    @State var isConfirmingUpload = false
    @State var isConfirmingReviewedSync = false

    init(mode: ASCFlowMode = .screenshots) {
        _model = State(initialValue: ASCUploadFlowModel(mode: mode))
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
            .task {
                model.bind(document: state)
                #if os(iOS)
                model.navigationDidAdvance = { path.append($0) }
                model.navigationWillRetreat = {
                    if path.last == .uploading || path.last == .done { path.removeLast() }
                }
                #endif
                await model.loadAppsIfNeeded()
            }
            .onDisappear { model.tearDown() }
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
                        model.startReviewedScreenshotSync()
                    } else {
                        model.startDirectScreenshotSync()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(confirmationMessage)
            }
    }

    #if os(macOS)
    private var macBody: some View {
        UploadWizardShell(showsBanner: model.credentials.isDemoMode) {
            header
        } banner: {
            demoModeBanner
        } content: {
            content
        } footer: {
            footer
        }
    }
    #endif
}
