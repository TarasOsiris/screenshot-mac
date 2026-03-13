import SwiftUI

@main
struct ScreenshotBroApp: App {
    @State private var appState = AppState()
    @AppStorage("appearance") private var appearance = "auto"

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
                .preferredColorScheme(preferredColorScheme)
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
                            appState.copySelectedShape()
                        }
                    }
                    .keyboardShortcut("c", modifiers: .command)

                    Button("Paste") {
                        if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView {
                            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                        } else {
                            appState.pasteShape()
                        }
                    }
                    .keyboardShortcut("v", modifiers: .command)

                    Button("Select All") {
                        NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                    }
                    .keyboardShortcut("a", modifiers: .command)

                    Button("Duplicate") {
                        if appState.selectedShapeId != nil {
                            appState.duplicateSelectedShape()
                        } else if let rowId = appState.selectedRowId {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                appState.duplicateRow(rowId)
                            }
                        }
                    }
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(appState.selectedShapeId == nil && appState.selectedRowId == nil)

                    Button("Delete") {
                        if appState.selectedShapeId != nil {
                            appState.deleteSelectedShape()
                        }
                    }
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(appState.selectedShapeId == nil)

                    Button("Deselect") {
                        if appState.selectedShapeId != nil {
                            appState.selectedShapeId = nil
                        } else {
                            appState.deselectAll()
                        }
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(appState.selectedShapeId == nil && appState.selectedRowId == nil)
                }

                Divider()

                Section {
                    Button("Bring to Front") {
                        appState.bringSelectedShapeToFront()
                    }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                    .disabled(appState.selectedShapeId == nil)

                    Button("Send to Back") {
                        appState.sendSelectedShapeToBack()
                    }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                    .disabled(appState.selectedShapeId == nil)
                }

                Divider()

                Section {
                    Button("Nudge Left") { appState.nudgeSelectedShape(dx: -1, dy: 0) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(appState.selectedShapeId == nil)

                    Button("Nudge Right") { appState.nudgeSelectedShape(dx: 1, dy: 0) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(appState.selectedShapeId == nil)

                    Button("Nudge Up") { appState.nudgeSelectedShape(dx: 0, dy: -1) }
                    .keyboardShortcut(.upArrow, modifiers: [])
                    .disabled(appState.selectedShapeId == nil)

                    Button("Nudge Down") { appState.nudgeSelectedShape(dx: 0, dy: 1) }
                    .keyboardShortcut(.downArrow, modifiers: [])
                    .disabled(appState.selectedShapeId == nil)

                    Button("Nudge Left ×10") { appState.nudgeSelectedShape(dx: -10, dy: 0) }
                    .keyboardShortcut(.leftArrow, modifiers: .shift)
                    .disabled(appState.selectedShapeId == nil)

                    Button("Nudge Right ×10") { appState.nudgeSelectedShape(dx: 10, dy: 0) }
                    .keyboardShortcut(.rightArrow, modifiers: .shift)
                    .disabled(appState.selectedShapeId == nil)

                    Button("Nudge Up ×10") { appState.nudgeSelectedShape(dx: 0, dy: -10) }
                    .keyboardShortcut(.upArrow, modifiers: .shift)
                    .disabled(appState.selectedShapeId == nil)

                    Button("Nudge Down ×10") { appState.nudgeSelectedShape(dx: 0, dy: 10) }
                    .keyboardShortcut(.downArrow, modifiers: .shift)
                    .disabled(appState.selectedShapeId == nil)
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
        }

        Settings {
            SettingsView()
        }
    }
}
