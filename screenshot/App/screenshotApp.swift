import SwiftUI

@main
struct ScreenshotBroApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .defaultSize(width: 1100, height: 700)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(after: .pasteboard) {
                Section {
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

                    Button("Deselect All") {
                        appState.deselectShape()
                    }
                    .keyboardShortcut(.escape, modifiers: [])
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
        }

        Settings {
            SettingsView()
        }
    }
}
