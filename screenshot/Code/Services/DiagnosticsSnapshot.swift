import Foundation

/// The plain-text block a user pastes into a support email. Its job is to make an emailed report
/// self-contained — above all to carry `DiagnosticsIdentity.installId`, which is what turns
/// "the app crashed" into a Sentry search.
///
/// Deliberately untranslated: it is written for whoever reads the support inbox, not for the user.
/// Same privacy rule as every Sentry payload — counts, enum names, booleans, and our own
/// identifiers only. Never project, row, or locale names, user file names, or any user-written text.
@MainActor
enum DiagnosticsSnapshot {
    static func text(state: AppState, store: StoreService?) -> String {
        var lines: [String] = []

        lines.append("Screenshot Bro \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber)) · \(platformLine())")
        lines.append("Install ID   \(DiagnosticsIdentity.installId)")
        if let first = DiagnosticsIdentity.firstVersion {
            lines.append("First seen   \(first)")
        }
        if let appUserID = store?.appUserID {
            lines.append("RevenueCat   \(appUserID)")
        }
        lines.append("Plan         \(store?.isProUnlocked == true ? "Pro" : "Free")")
        lines.append("Storage      \(storageLine())")
        lines.append("Language     \(languageLine())")
        lines.append("Projects     \(state.projects.count) · \(activeDocumentLine(state: state))")
        if let freeDiskMB {
            lines.append("Free disk    \(freeDiskMB) MB")
        }

        return lines.joined(separator: "\n")
    }

    private static func platformLine() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if os(macOS)
        let name = "macOS"
        #else
        let name = "iPadOS/iOS"
        #endif
        return "\(name) \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    /// The third state matters: the sync toggle is on but the container never resolved, which is a
    /// real failure mode that otherwise looks identical to working iCloud sync.
    private static func storageLine() -> String {
        let sync = ICloudSyncService.shared
        guard sync.isEnabled else { return "local" }
        return sync.iCloudContainerURL == nil ? "iCloud (container unavailable)" : "iCloud"
    }

    private static func languageLine() -> String {
        let active = Bundle.main.preferredLocalizations.first ?? "unknown"
        let override = UserDefaults.standard.string(forKey: AppSettingsKeys.appLanguageOverride) ?? ""
        return override.isEmpty ? active : "\(active) (override: \(override))"
    }

    private static func activeDocumentLine(state: AppState) -> String {
        let templates = state.rows.reduce(0) { $0 + $1.templates.count }
        let shapes = state.rows.reduce(0) { $0 + $1.shapes.count }
        return "Active: \(state.rows.count) rows, \(templates) templates, \(shapes) shapes, "
            + "\(state.localeState.locales.count) locales, \(state.screenshotImages.count) images"
    }

    private static var freeDiskMB: Int? {
        let values = try? PersistenceService.rootURL.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        guard let bytes = values?.volumeAvailableCapacityForImportantUsage else { return nil }
        return Int(bytes / 1_000_000)
    }
}
