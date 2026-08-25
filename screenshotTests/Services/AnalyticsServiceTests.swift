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
        AnalyticsService.screen(.editor)
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

    /// `$screen_name` is the wire name, so a collision silently merges two parts of the app into
    /// one line on every screen-view chart.
    @Test func screenNamesAreUniqueAndNonEmpty() {
        let rawValues = AnalyticsService.Screen.allCases.map(\.rawValue)
        #expect(rawValues.allSatisfy { !$0.isEmpty })
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test func screenNamesAreSnakeCase() {
        for rawValue in AnalyticsService.Screen.allCases.map(\.rawValue) {
            #expect(rawValue.allSatisfy { $0.isLowercase || $0 == "_" }, "\(rawValue) is not snake_case")
        }
    }

    /// Screen names are also event names in every sense that matters downstream — keeping the two
    /// vocabularies disjoint means a PostHog filter is never ambiguous about which it matched.
    @Test func screenNamesDoNotCollideWithEventNames() {
        let events = Set(AnalyticsService.Event.allCases.map(\.rawValue))
        for screen in AnalyticsService.Screen.allCases.map(\.rawValue) {
            #expect(!events.contains(screen), "\(screen) is both a screen and an event")
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
        // Ours, not the user's: a random per-session UUID that joins MCP tool calls to a session.
        #expect(AnalyticsService.allowsProperty(key: "mcp_session_id", value: UUID().uuidString))
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
        #expect(AnalyticsService.allowsProperty(key: "tool_call_count", value: "five") == false)
        #expect(AnalyticsService.allowsProperty(key: "distinct_tool_count", value: "three") == false)
    }

    /// The SDK's own context (`$os_name`, `$device_model`, `$locale`) is device metadata, not
    /// user content, and must survive the filter.
    @Test func sdkContextPropertiesPassThrough() {
        #expect(AnalyticsService.allowsProperty(key: "$os_name", value: "macOS"))
        #expect(AnalyticsService.allowsProperty(key: "$device_model", value: "Mac16,10"))
    }

    /// `$screen_name` carries a `Screen` raw value — ours, not the user's — and the SDK stamps it
    /// onto later events too. If the scrubber ever stopped honouring the `$` prefix, screen views
    /// would arrive nameless rather than fail loudly.
    @Test func screenNamePropertyPassesThrough() {
        for rawValue in AnalyticsService.Screen.allCases.map(\.rawValue) {
            #expect(AnalyticsService.allowsProperty(key: "$screen_name", value: rawValue))
        }
    }
}
