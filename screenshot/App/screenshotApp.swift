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
                    Button("Zoom In") {
                        withAnimation(.smooth(duration: 0.3)) {
                            appState.zoomLevel = min(ZoomConstants.max, appState.zoomLevel + ZoomConstants.step)
                        }
                    }
                    .keyboardShortcut("+", modifiers: .command)

                    Button("Zoom Out") {
                        withAnimation(.smooth(duration: 0.3)) {
                            appState.zoomLevel = max(ZoomConstants.min, appState.zoomLevel - ZoomConstants.step)
                        }
                    }
                    .keyboardShortcut("-", modifiers: .command)

                    Button("Actual Size") {
                        withAnimation(.smooth(duration: 0.3)) {
                            appState.zoomLevel = 1.0
                        }
                    }
                    .keyboardShortcut("0", modifiers: .command)
                }
            }
        }

        Settings {
            SettingsView()
        }
    }
}
