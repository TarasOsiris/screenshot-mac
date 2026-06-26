import StoreKit
import SwiftUI

@main
struct ScreenshotBroApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @State private var appState = AppState()
    @State private var storeService = StoreService()
    #if os(iOS)
    @State private var appNavigationRouter = AppNavigationRouter()
    #endif
    @AppStorage("appearance") private var appearance = "auto"
    #if os(iOS)
    @AppStorage(OnboardingPersistence.completedKey) private var onboardingCompleted = false
    /// Drives dismissal of the iPhone welcome cover. The cover's isPresented binding is get-only,
    /// and writing the shared `onboardingCompleted` @AppStorage from inside OnboardingView does not
    /// reliably re-evaluate this App-level binding — so this transient @State is the dismissal signal.
    @State private var welcomeDismissed = false
    #endif
    #if DEBUG && os(macOS)
    @State private var isDebugTemplateSavePresented = false
    @State private var debugTemplateName = ""
    @State private var debugTemplateError: String?
    @State private var debugExistingTemplates: [String] = []
    @State private var isDebugProjectManagerPresented = false
    #endif

    private var preferredColorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    init() {
        OnboardingPersistence.prepareForLaunch()
    }

    #if os(macOS)
    // Any focused text view — the canvas inline editor *or* an ordinary field editor
    // (font size, row label, locale name, …) — owns Cmd+Z so typing undoes in place.
    // Matches the firstResponder check used by the Cut/Copy/Paste commands below.
    private var focusedTextView: NSTextView? {
        NSApp.keyWindow?.firstResponder as? NSTextView
    }

    // While editing a canvas text shape, the inline editor owns undo. Route to its isolated
    // session manager directly (captured on the format controller) rather than chasing the
    // first responder: any format-bar interaction (font-size menu, color picker, B/I buttons)
    // can move first responder off the text view, and `textView.undoManager` resolves up the
    // responder chain rather than to the session manager. `isEditingText` is observed, so the
    // command's enablement re-evaluates synchronously the moment editing begins.
    private var inlineEditorUndoManager: UndoManager? {
        appState.isEditingText ? appState.richTextFormatController?.undoManager : nil
    }

    private var textEditorHasFocus: Bool {
        focusedTextView != nil
    }

    // While editing text the command is always available (its manager owns undo); otherwise a
    // focused field owns it, falling back to the document's own undo availability.
    private func commandDisabled(documentActionAvailable: Bool) -> Bool {
        if appState.isEditingText { return false }
        return focusedTextView != nil ? false : !documentActionAvailable
    }

    private var undoCommandDisabled: Bool {
        commandDisabled(documentActionAvailable: appState.canUndoDocumentAction)
    }

    private var redoCommandDisabled: Bool {
        commandDisabled(documentActionAvailable: appState.canRedoDocumentAction)
    }

    // Drive the focused text view's *own* undo manager directly. The inline editor uses a
    // private session manager (InlineTextEditor.Coordinator), so routing through the window's
    // undo: would miss it and undo nothing. When a text view is focused it always owns undo —
    // never fall through to the document, which would undo a different screenshot.
    private func performEditingOrDocumentCommand(
        textViewAction: (UndoManager) -> Void,
        documentAction: () -> Void
    ) {
        if appState.isEditingText {
            (inlineEditorUndoManager ?? focusedTextView?.undoManager).map(textViewAction)
        } else if let textView = focusedTextView {
            textView.undoManager.map(textViewAction)
        } else {
            documentAction()
        }
    }

    private func performUndoCommand() {
        performEditingOrDocumentCommand(textViewAction: { $0.undo() }, documentAction: appState.undoDocumentAction)
    }

    private func performRedoCommand() {
        performEditingOrDocumentCommand(textViewAction: { $0.redo() }, documentAction: appState.redoDocumentAction)
    }
    #endif

    var body: some Scene {
        #if os(macOS)
        Window("Screenshot Bro", id: AppRootView.windowID) {
            AppRootView()
                .environment(appState)
                .environment(storeService)
                .preferredColorScheme(preferredColorScheme)
                .background(WindowSceneBridge(role: .main))
                .task { storeService.start() }
                #if DEBUG
                .task {
                    debugRefreshExistingTemplates()
                }
                .alert("Save as New Template", isPresented: $isDebugTemplateSavePresented) {
                    TextField("Template name", text: $debugTemplateName)
                    Button("Save") {
                        let name = debugTemplateName
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: " ", with: "_")
                            .lowercased()
                        guard !name.isEmpty else { return }
                        debugSaveTemplate(name: name)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Enter a directory name for the template (e.g. my_template).")
                }
                .sheet(isPresented: $isDebugProjectManagerPresented) {
                    DebugProjectManagerView(state: appState)
                }
                .alert("Template Error", isPresented: Binding(
                    get: { debugTemplateError != nil },
                    set: { if !$0 { debugTemplateError = nil } }
                )) {
                    Button("OK") { debugTemplateError = nil }
                } message: {
                    Text(debugTemplateError ?? "")
                }
                #endif
        }
        .defaultSize(width: 1100, height: 700)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))

        Window("New Project", id: NewProjectWindowView.windowID) {
            NewProjectWindowView()
                .environment(appState)
                .environment(storeService)
                .preferredColorScheme(preferredColorScheme)
        }
        .defaultSize(width: 760, height: 620)
        .windowResizability(.contentMinSize)

        Window("Screenshot Bro Help", id: HelpView.windowID) {
            HelpView()
                .preferredColorScheme(preferredColorScheme)
        }
        .defaultSize(width: 920, height: 640)

        .commands {
            NewProjectCommands()
            MainWindowCommands()
            HelpCommands()

            CommandGroup(replacing: .undoRedo) {
                Button("Undo", action: performUndoCommand)
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(undoCommandDisabled)

                Button("Redo", action: performRedoCommand)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(redoCommandDisabled)
            }

            CommandGroup(replacing: .pasteboard) {
                Section {
                    Button("Cut") {
                        NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                    }
                    .keyboardShortcut("x", modifiers: .command)

                    Button("Copy") {
                        if focusedTextView != nil {
                            NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                        } else {
                            appState.copySelectedShapes()
                        }
                    }
                    .keyboardShortcut("c", modifiers: .command)

                    Button("Paste") {
                        if focusedTextView != nil {
                            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                        } else {
                            appState.pasteShapes()
                        }
                    }
                    .keyboardShortcut("v", modifiers: .command)

                    Button("Select All") {
                        if focusedTextView != nil {
                            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                        } else {
                            appState.selectAllShapesInRow()
                        }
                    }
                    .keyboardShortcut("a", modifiers: .command)

                    Button("Duplicate") {
                        if appState.hasSelection {
                            appState.duplicateSelectedShapes()
                        } else if let rowId = appState.selectedRowId {
                            storeService.requirePro(
                                allowed: storeService.canAddRow(currentCount: appState.rows.count),
                                context: .rowLimit
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    appState.duplicateRow(rowId)
                                }
                            }
                        }
                    }
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(!appState.hasSelection && appState.selectedRowId == nil)

                    Button("Delete") {
                        if appState.hasSelection {
                            appState.deleteSelectedShape()
                        }
                    }
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(!appState.hasSelection || appState.isEditingText)

                    Button("Deselect") {
                        if appState.hasSelection {
                            appState.selectedShapeIds = []
                        } else {
                            appState.deselectAll()
                        }
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(!appState.hasSelection && appState.selectedRowId == nil)

                    Button(appState.isSelectionFullyLocked ? "Unlock" : "Lock") {
                        appState.toggleLockOnSelection()
                    }
                    .keyboardShortcut("l", modifiers: .command)
                    .disabled(!appState.hasSelection || appState.isEditingText)
                }

                Divider()

                Section {
                    Button("Bring to Front") {
                        appState.bringSelectedShapesToFront()
                    }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                    .disabled(!appState.hasSelection)

                    Button("Send to Back") {
                        appState.sendSelectedShapesToBack()
                    }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                    .disabled(!appState.hasSelection)
                }

                Divider()

                // Arrow key nudge is handled via NSEvent local monitor
                // so that arrow keys work normally in text fields and alerts.
            }

            CommandGroup(before: .toolbar) {
                Section {
                    Button("Zoom In") { appState.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)

                    Button("Zoom Out") { appState.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)

                    Button("Actual Size") { appState.resetZoom() }
                    .keyboardShortcut("0", modifiers: .command)

                    Button("Focus on Selection") { appState.focusOnSelection() }
                    .keyboardShortcut("f", modifiers: [])
                    .disabled(!appState.hasSelection || appState.isEditingText)
                }
            }

            CommandMenu("Language") {
                Button("Previous Language") {
                    appState.cycleLocaleBackward()
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(appState.localeState.locales.count < 2)

                Button("Next Language") {
                    appState.cycleLocaleForward()
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(appState.localeState.locales.count < 2)

                Divider()

                Button("Switch to Base Language") {
                    appState.setActiveLocale(appState.localeState.baseLocaleCode)
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .disabled(appState.localeState.isBaseLocale)

                if appState.localeState.locales.count > 1 {
                    Divider()

                    Section("Switch To") {
                        ForEach(appState.localeState.locales) { locale in
                            Button(locale.flagLabel) {
                                appState.setActiveLocale(locale.code)
                            }
                            .disabled(locale.code == appState.localeState.activeLocaleCode)
                        }
                    }
                }

                Divider()

                let translationProgress = appState.translationProgress()

                Button("Auto-Translate Missing Text") {
                    appState.pendingLocaleMenuRequest = .autoTranslateMissing
                }
                .disabled(
                    appState.localeState.isBaseLocale ||
                    translationProgress.total == 0 ||
                    translationProgress.translated >= translationProgress.total
                )

                Button("Re-Translate All Text...") {
                    appState.pendingLocaleMenuRequest = .reTranslateAll
                }
                .disabled(appState.localeState.isBaseLocale || translationProgress.total == 0)

                Button("Revert to Base Language...") {
                    appState.pendingLocaleMenuRequest = .revertToBase
                }
                .disabled(!appState.localeState.activeLocaleHasOverrides)

                Divider()

                Button("Edit Translations...") {
                    appState.pendingLocaleMenuRequest = .editTranslations
                }
                .disabled(appState.localeState.locales.count < 2 || translationProgress.total == 0)

                Button("Manage Languages...") {
                    appState.pendingLocaleMenuRequest = .manageLocales
                }
            }

            #if DEBUG
            CommandMenu("Debug") {
                Button("Run Coach Tour") {
                    appState.startCoach(persistOnEnd: false)
                }
                .disabled(appState.activeProjectId == nil)

                Divider()

                Button("Manage Projects...") {
                    isDebugProjectManagerPresented = true
                }

                Menu("Save Current Project as Template") {
                    Button("New Template...") {
                        debugTemplateName = ""
                        debugTemplateError = nil
                        isDebugTemplateSavePresented = true
                    }
                    .disabled(appState.activeProjectId == nil)

                    if !debugExistingTemplates.isEmpty {
                        Divider()
                        Section("Override Existing") {
                            ForEach(debugExistingTemplates, id: \.self) { name in
                                Button(name) {
                                    debugSaveTemplate(name: name)
                                }
                            }
                        }
                    }
                }
                .disabled(appState.activeProjectId == nil)

                if !debugExistingTemplates.isEmpty {
                    Menu("Open Template") {
                        ForEach(debugExistingTemplates, id: \.self) { name in
                            Button(name) {
                                debugOpenTemplate(name: name)
                            }
                        }
                    }
                }

                Button("Regenerate All Previews") {
                    guard let bundleURL = DebugTemplateService.getTemplatesBundleURL() else { return }
                    DebugTemplateService.regenerateAllPreviews(bundleURL: bundleURL)
                }

                Button("Generate Missing Previews") {
                    guard let bundleURL = DebugTemplateService.getTemplatesBundleURL() else { return }
                    DebugTemplateService.generateMissingPreviews(bundleURL: bundleURL)
                }

                Divider()

                DebugRequestReviewButton()

                Button("Reset App Review State") {
                    for key in ["reviewExportCount", "reviewLastPromptedVersion", "reviewFirstExportDate", "reviewLastPromptDate"] {
                        UserDefaults.standard.removeObject(forKey: key)
                    }
                }
            }
            #endif
        }

        Settings {
            SettingsView()
                .environment(storeService)
                .preferredColorScheme(preferredColorScheme)
        }
        #else
        WindowGroup {
            iPadRootView()
                .environment(appState)
                .environment(storeService)
                .environment(appNavigationRouter)
                .preferredColorScheme(preferredColorScheme)
                .task { storeService.start() }
                .fullScreenCover(isPresented: Binding(
                    get: {
                        OnboardingPersistence.launchWelcomeSupportedOnDevice
                            && !onboardingCompleted && !welcomeDismissed
                    },
                    set: { _ in }
                )) {
                    OnboardingView(
                        persistCompletion: true,
                        onComplete: { welcomeDismissed = true }
                    )
                    .environment(storeService)
                    .interactiveDismissDisabled()
                }
        }
        #endif
    }

    #if DEBUG && os(macOS)
    private func withDebugBundleAccess<T>(_ body: (URL) throws -> T) rethrows -> T? {
        guard let bundleURL = DebugTemplateService.getTemplatesBundleURL() else { return nil }
        let didAccess = bundleURL.startAccessingSecurityScopedResource()
        defer { if didAccess { bundleURL.stopAccessingSecurityScopedResource() } }
        return try body(bundleURL)
    }

    private func debugRefreshExistingTemplates() {
        debugExistingTemplates = withDebugBundleAccess { bundleURL in
            DebugTemplateService.existingTemplateNames(at: bundleURL)
        } ?? []
    }

    private func debugOpenTemplate(name: String) {
        guard let _ = withDebugBundleAccess({ bundleURL in
            let templateURL = bundleURL.appendingPathComponent(name, isDirectory: true)
            let template = ProjectTemplate(id: name, name: name, url: templateURL, previewImage: nil, menuIcon: nil)
            appState.createProjectFromTemplate(template)
            debugRefreshExistingTemplates()
        }) else {
            debugTemplateError = "Could not access Templates.bundle. Make sure the bundle exists in the project source directory."
            return
        }
        if let error = appState.saveError {
            debugTemplateError = error
            appState.saveError = nil
        }
    }

    private func debugSaveTemplate(name: String) {
        appState.saveCurrentProject()
        guard let projectId = appState.activeProjectId else { return }
        _ = withDebugBundleAccess { bundleURL in
            do {
                try DebugTemplateService.saveProjectAsTemplate(projectId: projectId, templateName: name, bundleURL: bundleURL)
                debugExistingTemplates = DebugTemplateService.existingTemplateNames(at: bundleURL)
            } catch {
                debugTemplateError = error.localizedDescription
            }
        }
    }
    #endif
}

#if os(macOS)
private struct NewProjectCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project...") {
                openWindow(id: NewProjectWindowView.windowID)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}

private struct MainWindowCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button("Show Main Window") {
                AppWindowManager.shared.showMainWindow()
            }
        }
    }
}

private struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Screenshot Bro Help") {
                openWindow(id: HelpView.windowID)
                // openWindow is async; the NSWindow isn't registered until the
                // next runloop, so defer the raise so it can come to front even
                // when the main window holds an active text selection.
                DispatchQueue.main.async {
                    AppWindowManager.shared.raiseHelpWindow()
                }
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return false }
        AppWindowManager.shared.showMainWindow()
        return true
    }
}
#endif

#if DEBUG && os(macOS)
private struct DebugRequestReviewButton: View {
    @Environment(\.requestReview) private var requestReview
    var body: some View {
        Button("Request App Review Now") { requestReview() }
    }
}
#endif
