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

    /// A project locale Play has no listing language for.
    private func unsupportedLocale(_ code: String, enabled: Bool = false) -> Target {
        Target(appLocaleCode: code, appLocaleLabel: code, playLanguageCode: nil, isEnabled: enabled)
    }

    private func mappedLocale(_ code: String, to play: String) -> Target {
        Target(appLocaleCode: code, appLocaleLabel: code, playLanguageCode: play, isEnabled: true)
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

    /// The 4.16 bug: "en" and "en-US" both map to Play's en-US, so one row claimed the same slot
    /// twice and was reported as colliding with itself — an error naming one row twice, which no
    /// amount of disabling rows could clear.
    @Test func aRowWhoseLocalesCollapseOntoOnePlayLanguageNamesTheLanguages() {
        let row = plan(locales: [mappedLocale("en", to: "en-US"), mappedLocale("en-US", to: "en-US")])
        let issues = GooglePlayUploadValidator.validate(
            packageName: "com.example.app",
            plans: [row],
            isDemoMode: false
        )
        let errors = issues.filter { $0.severity == .error }
        #expect(errors.count == 1)
        #expect(errors.first?.message == "en and en-US both upload to Play's en-US listing.")
        #expect(errors.allSatisfy { !$0.message.contains("same Play listing slot") }, "this is not a row clash")
    }

    @Test func languagesPlayCannotAcceptWarnButDoNotBlock() {
        let row = plan(locales: [locale("en-US"), unsupportedLocale("ar-SA")])
        let issues = GooglePlayUploadValidator.validate(
            packageName: "com.example.app",
            plans: [row],
            isDemoMode: false
        )
        #expect(!issues.hasErrors)
        #expect(issues.contains { $0.severity == .warning && $0.message.contains("ar-SA") })
    }

    /// An unsupported language files no claim, so it can never be mistaken for a collision.
    @Test func twoUnsupportedLanguagesDoNotCollide() {
        let row = plan(locales: [locale("en-US"), unsupportedLocale("ar-SA", enabled: true), unsupportedLocale("uz", enabled: true)])
        let issues = GooglePlayUploadValidator.validate(
            packageName: "com.example.app",
            plans: [row],
            isDemoMode: false
        )
        #expect(!issues.hasErrors)
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
