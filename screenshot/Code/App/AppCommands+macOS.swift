#if os(macOS)
import AppKit
import SwiftUI

struct NewProjectCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project…") {
                openWindow(id: NewProjectWindowView.windowID)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}

struct MainWindowCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button("Show Main Window") {
                AppWindowManager.shared.showMainWindow()
            }
        }
    }
}

struct SettingsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                openWindow(id: SettingsView.windowID)
                // Same deferred raise as HelpCommands: openWindow registers the
                // NSWindow on the next runloop.
                DispatchQueue.main.async {
                    AppWindowManager.shared.raiseSettingsWindow()
                }
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

#if !DIRECT_DISTRIBUTION
/// The passive way to rate the app: Guideline 5.6.1 rules out a custom review prompt.
struct RateAppCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Rate Screenshot Bro on the App Store…") {
                AnalyticsService.capture(.rateAppTapped, [.source: "menu"])
                NSWorkspace.shared.open(AppLinks.rateOnAppStore)
            }
        }
    }
}
#endif

struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Screenshot Bro Help") {
                AppWindowManager.shared.showHelp(using: openWindow)
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}
#endif
