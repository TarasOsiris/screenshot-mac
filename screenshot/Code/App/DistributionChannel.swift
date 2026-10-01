import Foundation

/// Which storefront this binary was built for. The `screenshot Direct` target (Developer ID,
/// Sparkle, Pro sold on the web through RevenueCat Web Billing) is the only one that defines
/// `DIRECT_DISTRIBUTION`; the App Store target must never see it.
nonisolated enum DistributionChannel: String {
    case appStore = "app_store"
    case direct

    #if DIRECT_DISTRIBUTION
    static let current: DistributionChannel = .direct
    #else
    static let current: DistributionChannel = .appStore
    #endif

    static var isDirect: Bool { current == .direct }

    /// Redirects to the RevenueCat Web Purchase Link, so the checkout URL can change without a release.
    static let webCheckoutURL = URL(string: "https://screenshotbro.app/buy")!
}
