import StoreKit
import SwiftUI

extension ContentView {
    /// Sheets, alerts, covers, and window lifecycle attached to the editor shell.
    func contentModals(_ base: some View) -> some View {
        base
        .exportFailedAlert($exportFlow.errorMessage)
        .exportIncompleteAlert($exportFlow.incompleteMessage)
        #if os(iOS)
        .sheet(item: $exportFlow.pendingExport, onDismiss: { discardPendingExport() }) { _ in
            ExportDestinationSheet(title: pendingExportTitle) { destination in
                runPendingExport(to: destination)
            }
            .screenView(.exportDestination, restoring: .editor)
        }
        #endif
        .alert(resetTemplate != nil ? String(localized: "Reset Project from Template") : String(localized: "Reset Project"), isPresented: $isResettingProject) {
            Button("Reset", role: .destructive) {
                if let id = state.activeProjectId {
                    if let template = resetTemplate {
                        state.resetProjectFromTemplate(id, template: template)
                        resetTemplate = nil
                    } else {
                        state.resetProject(id)
                    }
                }
            }
            Button("Cancel", role: .cancel) { resetTemplate = nil }
        } message: {
            if let template = resetTemplate {
                Text("Are you sure you want to reset \"\(state.activeProject?.name ?? "")\" using the \"\(template.name)\" template? All current rows and shapes will be replaced. This cannot be undone.")
            } else {
                Text("Are you sure you want to reset \"\(state.activeProject?.name ?? "")\"? All rows and shapes will be removed. This cannot be undone.")
            }
        }
        .alert("Delete Project", isPresented: $isDeletingProject) {
            Button("Delete", role: .destructive) {
                if let id = state.activeProjectId {
                    state.deleteProject(id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(state.activeProject?.name ?? "")\"? This cannot be undone.")
        }
        // On iPad the paywall/celebration sheets live at the navigation root (`iPadRootView`)
        // so they also present from the Projects home screen, not just the pushed editor.
        #if os(macOS)
        .purchaseSheets(store: store, restoring: .editor)
        #endif
        // Upload wizards: fitted sheet on macOS, native full-screen screen on iPad.
        .platformAdaptiveSheet(isPresented: $showingASCUploadSheet) {
            UploadToAppStoreConnectView()
                .environment(state)
                .screenView(.ascUpload, restoring: .editor)
        }
        .platformAdaptiveSheet(isPresented: $showingASCMetadataSheet) {
            UploadToAppStoreConnectView(mode: .metadata)
                .environment(state)
                .screenView(.ascMetadata, restoring: .editor)
        }
        .platformAdaptiveSheet(isPresented: $showingASCExperimentSheet) {
            UploadExperimentToAppStoreConnectView()
                .environment(state)
                .screenView(.ascExperimentUpload, restoring: .editor)
        }
        .platformAdaptiveSheet(isPresented: $showingGooglePlayUploadSheet) {
            UploadToGooglePlayView()
                .environment(state)
                .screenView(.googlePlayUpload, restoring: .editor)
        }
        .sheet(item: $projectNamePrompt) { prompt in
            ProjectNameSheet(prompt: prompt)
        }
        #if os(macOS)
        .sheet(item: $showcasePresentation) { presentation in
            showcaseExportScreen(for: presentation)
                .presentationSizing(.page)
                .screenView(.showcaseExport, restoring: .editor)
        }
        #else
        // iPad: showcase export is a desktop-grade split view — present it as its own
        // full-screen screen with a native nav bar rather than a fitted sheet.
        .fullScreenCover(item: $showcasePresentation) { presentation in
            showcaseExportScreen(for: presentation)
                .exportFailedAlert($exportFlow.errorMessage)
                .screenView(.showcaseExport, restoring: .editor)
        }
        #endif
        .middleMousePan()
        .task {
            projectTemplates = await TemplateService.availableTemplatesAsync()
        }
        .onChange(of: isReviewPromptBlocked) { _, blocked in
            if !blocked { exportFlow.reviewPrompt.resume() }
        }
        // "Reveal in Finder after export" (or a switch to another app) leaves us behind just as the ask comes due.
        .onReceive(NotificationCenter.default.publisher(for: PlatformApp.didBecomeActiveNotification)) { _ in
            exportFlow.reviewPrompt.resume()
        }
        .onAppear {
            // `requestReview` is an environment value, so only a view can hand it over.
            exportFlow.reviewPrompt.requestReview = { [requestReview] in requestReview() }
            exportFlow.reviewPrompt.isClearToAsk = { !isReviewPromptBlocked && PlatformApp.isActive }
            #if os(iOS)
            if state.selectedRowId == nil, let firstRow = state.rows.first {
                state.selectRow(firstRow.id)
            }
            #endif
            scrollWheelZoom.install(state: state)
        }
        .onDisappear {
            scrollWheelZoom.remove()
            exportFlow.reviewPrompt.tearDown()
        }
    }

    /// Anything the system review prompt must not land on top of, or interrupt.
    private var isReviewPromptBlocked: Bool {
        exportFlow.isExporting || exportFlow.errorMessage != nil || exportFlow.incompleteMessage != nil
            || exportFlow.pendingExport != nil || showcasePresentation != nil || projectNamePrompt != nil
            || showingASCUploadSheet || showingASCMetadataSheet || showingASCExperimentSheet
            || showingGooglePlayUploadSheet || isDeletingProject || isResettingProject
            || store.showPaywall || store.purchaseCelebrationContext != nil || state.saveError != nil
    }
}
