#if os(macOS)
import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
struct MCPScreenshotTargetPlannerTests {
    private let version = ASCAppStoreVersion(
        id: "v1",
        attributes: .init(versionString: "1.0", appStoreState: "PREPARE_FOR_SUBMISSION", platform: "IOS")
    )
    private let localizations = [
        ASCAppStoreVersionLocalization(id: "loc-en", attributes: .init(locale: "en-US")),
        ASCAppStoreVersionLocalization(id: "loc-de", attributes: .init(locale: "de-DE")),
    ]

    private func iPhoneRow(label: String = "Hero") -> ScreenshotRow {
        makeTestRow(label: label, width: 1290, height: 2796)
    }

    @Test func eligibleRowTargetsEveryMappedLocale() {
        let row = iPhoneRow()
        let planned = MCPScreenshotTargetPlanner.targets(
            version: version, remoteLocalizations: localizations, rows: [row], localeCodes: ["en", "de"]
        )
        #expect(planned.issues.isEmpty)
        #expect(planned.targets.count == 1)
        #expect(planned.targets.first?.rowId == row.id)
        #expect(planned.targets.first?.localizations.map(\.id) == ["loc-en", "loc-de"])
    }

    @Test func unmappedLocaleIsReportedNotTargeted() {
        let planned = MCPScreenshotTargetPlanner.targets(
            version: version, remoteLocalizations: localizations, rows: [iPhoneRow()], localeCodes: ["en", "ja"]
        )
        #expect(planned.targets.first?.localizations.map(\.localeCode) == ["en"])
        #expect(planned.issues.count == 1)
        #expect(planned.issues.first?.contains("ja") == true)
    }

    @Test func excludedRowIsSkippedWithReason() {
        var row = iPhoneRow()
        row.excludeFromAppStoreConnect = true
        let planned = MCPScreenshotTargetPlanner.targets(
            version: version, remoteLocalizations: localizations, rows: [row], localeCodes: ["en"]
        )
        #expect(planned.targets.isEmpty)
        #expect(planned.issues.first?.contains("excluded") == true)
    }

    @Test func secondRowOfSameDisplayTypeCannotClaimTheSameSet() {
        let first = iPhoneRow(label: "First")
        let second = iPhoneRow(label: "Second")
        let planned = MCPScreenshotTargetPlanner.targets(
            version: version, remoteLocalizations: localizations, rows: [first, second], localeCodes: ["en"]
        )
        #expect(planned.targets.map(\.rowId) == [first.id])
        #expect(planned.issues.count == 1)
        #expect(planned.issues.first?.contains(second.id.uuidString) == true)
    }
}
#endif
