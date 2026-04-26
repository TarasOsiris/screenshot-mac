import SwiftUI

@main
struct ScreenshotBroApp: App {
    @State private var appState = AppState()
    @State private var storeService = StoreService()
    @AppStorage("appearance") private var appearance = "auto"
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    #if DEBUG
    @State private var isDebugTemplateSavePresented = false
    @State private var debugTemplateName = ""
    @State private var debugTemplateError: String?
    @State private var debugExistingTemplates: [String] = []
    @State private var isDebugProjectManagerPresented = false
    @State private var isDebugOnboardingPresented = false
    #endif

    private var preferredColorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(appState)
                .environment(storeService)
                .preferredColorScheme(preferredColorScheme)
                .task { storeService.start() }
                .sheet(isPresented: Binding(
                    get: { !onboardingCompleted },
                    set: { if !$0 { onboardingCompleted = true } }
                )) {
                    OnboardingView()
                        .interactiveDismissDisabled()
                }
                #if DEBUG
                .sheet(isPresented: $isDebugOnboardingPresented) {
                    OnboardingView(
                        persistCompletion: false,
                        onComplete: { isDebugOnboardingPresented = false }
                    )
                }
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

        .commands {
            NewProjectCommands()

            CommandGroup(replacing: .pasteboard) {
                Section {
                    Button("Cut") {
                        NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                    }
                    .keyboardShortcut("x", modifiers: .command)

                    Button("Copy") {
                        if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView {
                            NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                        } else {
                            appState.copySelectedShapes()
                        }
                    }
                    .keyboardShortcut("c", modifiers: .command)

                    Button("Paste") {
                        if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView {
                            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                        } else {
                            appState.pasteShapes()
                        }
                    }
                    .keyboardShortcut("v", modifiers: .command)

                    Button("Select All") {
                        if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView {
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

            CommandMenu("Locale") {
                Button("Previous Locale") {
                    appState.cycleLocaleBackward()
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(appState.localeState.locales.count < 2)

                Button("Next Locale") {
                    appState.cycleLocaleForward()
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(appState.localeState.locales.count < 2)

                Divider()

                Button("Switch to Base") {
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

                Button("Manage Locales...") {
                    appState.pendingLocaleMenuRequest = .manageLocales
                }
            }

            #if DEBUG
            CommandMenu("Debug") {
                Button("Show Onboarding...") {
                    isDebugOnboardingPresented = true
                }

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
            }
            #endif
        }

        Settings {
            SettingsView()
                .environment(storeService)
                .preferredColorScheme(preferredColorScheme)
        }
    }

    #if DEBUG
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
