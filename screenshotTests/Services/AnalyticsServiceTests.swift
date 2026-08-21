import Foundation
@testable import Screenshot_Bro
import Testing

@Suite(.serialized)
struct AnalyticsServiceTests {

    // MARK: - Test-run silence

    @Test func analyticsIsDisabledUnderTests() {
        #expect(AnalyticsService.isEnabled == false)
    }

    /// The debug opt-in must not be able to defeat the test guard: `SCREENSHOT_ENABLE_ANALYTICS`
    /// set in a scheme (to verify a local build by hand) would otherwise make every subsequent
    /// test run transmit, silently, on that machine only.
    @Test func debugOptInCannotEnableAnalyticsDuringTests() {
        #expect(PersistenceService.isRunningUnderXCTest)
        #expect(AnalyticsService.isEnabled == false)
    }

    /// The real guarantee: the host app launched and ran `start()`, and PostHog still never
    /// initialized — so there is no queue and no transport to send anything.
    @Test func postHogNeverStartsUnderTests() {
        #expect(AnalyticsService.isActive == false)
    }

    /// A future entry point that lazily initializes the SDK fails here rather than in real data.
    @Test func captureEntryPointsDoNotStartTheSDK() {
        AnalyticsService.start()
        AnalyticsService.capture(.appLaunched)
        AnalyticsService.capture(.exportFinished, [.imageCount: 3])
        AnalyticsService.setProfile([.pro: true])
        AnalyticsService.linkStoreUser("test-store-user")
        AnalyticsService.flush()
        #expect(AnalyticsService.isActive == false)
    }

    /// `linkStoreUser` must not have written its "already aliased" marker: the SDK never started,
    /// so no alias was actually sent, and persisting one would suppress the real alias forever.
    @Test func linkStoreUserLeavesNoMarkerWhenInactive() {
        #expect(UserDefaults.standard.string(forKey: AppSettingsKeys.analyticsAliasedStoreUserId) == nil)
    }

    // MARK: - Wire contract

    @Test func eventRawValuesAreUniqueAndNonEmpty() {
        let rawValues = AnalyticsService.Event.allCases.map(\.rawValue)
        #expect(rawValues.allSatisfy { !$0.isEmpty })
        // Raw values are the PostHog event names — a collision silently merges two funnels.
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test func eventNamesAreSnakeCase() {
        for rawValue in AnalyticsService.Event.allCases.map(\.rawValue) {
            #expect(rawValue.allSatisfy { $0.isLowercase || $0 == "_" }, "\(rawValue) is not snake_case")
        }
    }

    // MARK: - Property allowlist

    @Test func nonStringValuesAlwaysPass() {
        #expect(AnalyticsService.allowsProperty(key: "row_count", value: 4))
        #expect(AnalyticsService.allowsProperty(key: "cancelled", value: true))
        #expect(AnalyticsService.allowsProperty(key: "duration_ms", value: 1_200))
    }

    @Test func allowlistedKeysMayCarryStrings() {
        #expect(AnalyticsService.allowsProperty(key: "destination", value: "photos"))
        #expect(AnalyticsService.allowsProperty(key: "template_id", value: "gradient-hero"))
        #expect(AnalyticsService.allowsProperty(key: "store", value: "asc"))
    }

    /// The privacy claim in `privacy.tsx` is that no project, row, locale or user text ever leaves
    /// the device. This is what makes that structural rather than remembered.
    @Test func unknownKeysCannotCarryStrings() {
        #expect(AnalyticsService.allowsProperty(key: "project_name", value: "My Secret App") == false)
        #expect(AnalyticsService.allowsProperty(key: "row_label", value: "Onboarding") == false)
    }

    /// Numeric-only keys are numeric on purpose — `locale_count` exists so `locale` never has to.
    @Test func countKeysCannotCarryStrings() {
        #expect(AnalyticsService.allowsProperty(key: "locale_count", value: "de") == false)
        #expect(AnalyticsService.allowsProperty(key: "row_count", value: "three") == false)
    }

    /// The SDK's own context (`$os_name`, `$device_model`, `$locale`) is device metadata, not
    /// user content, and must survive the filter.
    @Test func sdkContextPropertiesPassThrough() {
        #expect(AnalyticsService.allowsProperty(key: "$os_name", value: "macOS"))
        #expect(AnalyticsService.allowsProperty(key: "$device_model", value: "Mac16,10"))
    }
}
