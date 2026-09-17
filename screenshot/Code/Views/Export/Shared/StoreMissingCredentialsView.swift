import SwiftUI

#if os(macOS)
/// Raises Settings to a section from inside a sheet. Settings is a separate window on macOS, so
/// this both opens and re-raises it — it may already be open behind the wizard.
struct OpenSettingsWindowButton: View {
    var section: SettingsView.SettingsSection = .appStoreConnect
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            SettingsWindowNavigation.shared.requestedSection = section
            openWindow(id: SettingsView.windowID)
            // openWindow registers the NSWindow on the next runloop; raise it then
            // so it comes forward even if it was already open behind this sheet.
            DispatchQueue.main.async {
                AppWindowManager.shared.raiseSettingsWindow()
            }
        } label: {
            Label("Open Settings", systemImage: "gearshape")
        }
        .buttonStyle(.borderedProminent)
    }
}
#endif

/// Which store's settings an "Open Settings" action lands on. One case per store rather than each
/// platform's own enum, so call sites don't need a `#if` mid-argument-list.
enum StoreSettingsTarget {
    case appStoreConnect
    case googlePlay

    #if os(macOS)
    var section: SettingsView.SettingsSection {
        switch self {
        case .appStoreConnect: .appStoreConnect
        case .googlePlay: .googlePlay
        }
    }
    #else
    var destination: iPadSettingsDestination {
        switch self {
        case .appStoreConnect: .appStoreConnect
        case .googlePlay: .googlePlay
        }
    }
    #endif
}

/// What a store wizard shows instead of its first step when no credentials are configured: why it
/// can't continue, and the one action that fixes it.
struct StoreMissingCredentialsView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let target: StoreSettingsTarget
    #if !os(macOS)
    @Environment(AppNavigationRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    #endif

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.horizontal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            #if os(macOS)
            OpenSettingsWindowButton(section: target.section)
            #else
            Button {
                router.openStoreSettings(target.destination)
                dismiss()
            } label: {
                Label("Open Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
