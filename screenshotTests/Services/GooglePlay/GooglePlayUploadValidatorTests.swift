import CoreGraphics
import Foundation
@testable import Screenshot_Bro
import Testing

struct GooglePlayUploadValidatorTests {
    private typealias Plan = GPRowPlan
    private typealias Target = GPLocaleTarget

    private func locale(_ play: String, enabled: Bool = true) -> Target {
        Target(appLocaleCode: play, appLocaleLabel: play, playLanguageCode: play, isEnabled: enabled)
    }

    private func plan(
        size: CGSize = CGSize(width: 1080, height: 1920),
        count: Int = 3,
        enabled: Bool = true,
        type: GPImageType = .phoneScreenshots,
        locales: [Target] = []
    ) -> Plan {
        Plan(
            id: UUID(),
            rowLabel: "Row",
            rowSize: size,
            templateCount: count,
            isEnabled: enabled,
            detectedAssetType: type,
            selectedAssetType: type,
            localeTargets: locales.isEmpty ? [locale("en-US")] : locales
        )
    }

    @Test func validPlanHasNoErrors() {
        let issues = GooglePlayUploadValidator.validate(
            packageName: "com.example.app",
            plans: [plan()],
            isDemoMode: false
        )
        #expect(!issues.hasErrors)
    }

    @Test func rejectsInvalidPackageName() {
        let issues = GooglePlayUploadValidator.validate(
            packageName: "not a package",
            plans: [plan()],
            isDemoMode: false
        )
        #expect(issues.hasErrors)
    }

    @Test func rejectsTooFewAndTooManyScreenshots() {
        #expect(GooglePlayUploadValidator.validate(packageName: "com.example.app", plans: [plan(count: 1)], isDemoMode: false).hasErrors)
        #expect(GooglePlayUploadValidator.validate(packageName: "com.example.app", plans: [plan(count: 9)], isDemoMode: false).hasErrors)
    }

    @Test func rejectsOutOfBoundsDimensions() {
        let issues = GooglePlayUploadValidator.validate(
            packageName: "com.example.app",
            plans: [plan(size: CGSize(width: 100, height: 2000))],
            isDemoMode: false
        )
        #expect(issues.hasErrors)
    }

    @Test func requiresAtLeastOneLanguage() {
        let issues = GooglePlayUploadValidator.validate(
            packageName: "com.example.app",
            plans: [plan(locales: [locale("en-US", enabled: false)])],
            isDemoMode: false
        )
        #expect(issues.hasErrors)
    }

    @Test func detectsDuplicateLanguageAndTypeAcrossRows() {
        let a = plan(locales: [locale("en-US")])
        let b = plan(locales: [locale("en-US")])
        let issues = GooglePlayUploadValidator.validate(
            packageName: "com.example.app",
            plans: [a, b],
            isDemoMode: false
        )
        #expect(issues.hasErrors)
    }

    @Test func demoModeSkipsPackageAndSoftensRowIssues() {
        // Bad package + too few screenshots, but in demo mode neither should hard-block.
        let issues = GooglePlayUploadValidator.validate(
            packageName: "",
            plans: [plan(count: 1)],
            isDemoMode: true
        )
        #expect(!issues.hasErrors)
        #expect(issues.contains { $0.severity == .warning })
    }
}

struct GooglePlayPackageNameTests {
    @Test func acceptsReverseDNSNames() {
        #expect(GooglePlayUploadValidator.isValidPackageName("com.example.myapp"))
        #expect(GooglePlayUploadValidator.isValidPackageName("com.example.my_app2"))
        #expect(GooglePlayUploadValidator.isValidPackageName("a.b"))
    }

    @Test func rejectsMalformedNames() {
        #expect(!GooglePlayUploadValidator.isValidPackageName(""))
        #expect(!GooglePlayUploadValidator.isValidPackageName("noseparator"))
        #expect(!GooglePlayUploadValidator.isValidPackageName("com..example"))
        #expect(!GooglePlayUploadValidator.isValidPackageName("com.example."))
        #expect(!GooglePlayUploadValidator.isValidPackageName("1com.example"), "segments must start with a letter")
        #expect(!GooglePlayUploadValidator.isValidPackageName("com.exa-mple"), "hyphens aren't allowed")
        #expect(!GooglePlayUploadValidator.isValidPackageName("com.éxample"), "non-ASCII letters aren't allowed")
    }
}
