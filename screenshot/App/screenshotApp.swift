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
            ContentView()
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
        .commands {
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

                Section {
                    let noShape = !appState.hasSelection || appState.isEditingText

                    Button("Nudge Left") { appState.nudgeSelectedShapes(dx: -1, dy: 0) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(noShape)

                    Button("Nudge Right") { appState.nudgeSelectedShapes(dx: 1, dy: 0) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(noShape)

                    Button("Nudge Up") { appState.nudgeSelectedShapes(dx: 0, dy: -1) }
                    .keyboardShortcut(.upArrow, modifiers: [])
                    .disabled(noShape)

                    Button("Nudge Down") { appState.nudgeSelectedShapes(dx: 0, dy: 1) }
                    .keyboardShortcut(.downArrow, modifiers: [])
                    .disabled(noShape)

                    Button("Nudge Left ×10") { appState.nudgeSelectedShapes(dx: -10, dy: 0) }
                    .keyboardShortcut(.leftArrow, modifiers: .shift)
                    .disabled(noShape)

                    Button("Nudge Right ×10") { appState.nudgeSelectedShapes(dx: 10, dy: 0) }
                    .keyboardShortcut(.rightArrow, modifiers: .shift)
                    .disabled(noShape)

                    Button("Nudge Up ×10") { appState.nudgeSelectedShapes(dx: 0, dy: -10) }
                    .keyboardShortcut(.upArrow, modifiers: .shift)
                    .disabled(noShape)

                    Button("Nudge Down ×10") { appState.nudgeSelectedShapes(dx: 0, dy: 10) }
                    .keyboardShortcut(.downArrow, modifiers: .shift)
                    .disabled(noShape)
                }
            }

            CommandGroup(before: .toolbar) {
                Section {
                    Button("Zoom In") { appState.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)

                    Button("Zoom Out") { appState.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)

                    Button("Actual Size") { appState.resetZoom() }
                    .keyboardShortcut("0", modifiers: .command)
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

                Button("Switch to Base Language") {
                    appState.setActiveLocale(appState.localeState.baseLocaleCode)
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .disabled(appState.localeState.isBaseLocale)
            }

            #if DEBUG
            CommandMenu("Debug") {
                Button("Manage Projects...") {
                    isDebugProjectManagerPresented = true
                }

                Divider()

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
            }
            #endif
        }

        Settings {
            SettingsView()
                .environment(storeService)
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
        _ = withDebugBundleAccess { bundleURL in
            let templateURL = bundleURL.appendingPathComponent(name, isDirectory: true)
            let template = ProjectTemplate(id: name, name: name, url: templateURL, previewImage: nil)
            appState.createProjectFromTemplate(template)
            debugRefreshExistingTemplates()
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
