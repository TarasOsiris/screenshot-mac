import Foundation
import Observation
import Synchronization

/// Beta features. A flag gates entry points only, so turning one off never drops data it wrote.
nonisolated enum FeatureFlags {
    /// Settings ▸ Beta ▸ A/B testing, readable from any thread; views read `BetaFeatures` to update live.
    static var abTesting: Bool { abTestingStorage.load(ordering: .relaxed) }

    fileprivate static let abTestingStorage = Atomic<Bool>(
        UserDefaults.standard.bool(forKey: AppSettingsKeys.betaABTesting)
    )
}

/// The Settings ▸ Beta toggles, observable so every view gated on one updates when it changes.
@MainActor
@Observable
final class BetaFeatures {
    static let shared = BetaFeatures()

    private(set) var isABTestingEnabled = FeatureFlags.abTesting

    /// `persist: false` is for tests, which must not change the developer's own setting.
    func setABTesting(_ enabled: Bool, persist: Bool = true) {
        isABTestingEnabled = enabled
        FeatureFlags.abTestingStorage.store(enabled, ordering: .relaxed)
        if persist { UserDefaults.standard.set(enabled, forKey: AppSettingsKeys.betaABTesting) }
    }
}

extension Array where Element == ScreenshotVariant {
    /// None while A/B testing is off, so an `isEmpty` check carries the flag.
    var active: [ScreenshotVariant] { FeatureFlags.abTesting ? self : [] }
}
