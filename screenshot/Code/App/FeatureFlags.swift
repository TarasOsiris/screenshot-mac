import Foundation

/// Gates entry points only; persistence stays on everywhere so Release never drops data Debug wrote.
nonisolated enum FeatureFlags {
    /// A/B variants and App Store product-page experiments.
    static let abTesting: Bool = {
        #if DEBUG
        true
        #else
        false
        #endif
    }()
}

extension Array where Element == ScreenshotVariant {
    /// None while A/B testing is off, so an `isEmpty` check carries the flag.
    var active: [ScreenshotVariant] { FeatureFlags.abTesting ? self : [] }
}
