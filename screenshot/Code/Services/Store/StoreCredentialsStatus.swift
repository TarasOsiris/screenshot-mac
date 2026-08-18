import Foundation

/// The four states a store credential pane reports. App Store Connect and Google Play each had
/// their own copy of this enum plus four `switch`es over it; the titles and SF Symbols were
/// identical, and only the per-state prose differs (so that stays with each store).
nonisolated enum StoreCredentialsStatus: Equatable, CaseIterable {
    /// Demo mode is on; the wizard never contacts the store.
    case demoMode
    /// A connection test has succeeded this session.
    case connected
    /// Credentials are present but untested.
    case readyToTest
    /// Credentials are incomplete.
    case finishSetup

    /// Demo mode wins over everything — it is what lets App Review run the flow with no
    /// credentials at all — and a passing test outranks merely having credentials.
    static func resolve(isDemoMode: Bool, connectionTestPassed: Bool, hasCredentials: Bool) -> Self {
        if isDemoMode { return .demoMode }
        if connectionTestPassed { return .connected }
        return hasCredentials ? .readyToTest : .finishSetup
    }

    var title: String {
        switch self {
        case .demoMode: String(localized: "Demo mode")
        case .connected: String(localized: "Connected")
        case .readyToTest: String(localized: "Ready to test")
        case .finishSetup: String(localized: "Finish setup")
        }
    }

    var symbolName: String {
        switch self {
        case .demoMode: "theatermasks.fill"
        case .connected: "checkmark.seal.fill"
        case .readyToTest: "bolt.horizontal.circle.fill"
        case .finishSetup: "key.horizontal"
        }
    }
}
