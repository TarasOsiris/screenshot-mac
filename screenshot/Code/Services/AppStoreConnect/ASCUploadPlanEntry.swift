import Foundation

/// The plan fanned out to one row per (destination, row, locale), plus the two groupings
/// the summary panel presents it in.
struct ASCUploadPlanEntry: Identifiable {
    let id: String
    let destinationId: String
    let destinationLabel: String
    let destinationPlatform: ASCPlatform?
    let rowPlanId: UUID
    let rowLabel: String
    let sourceSizeLabel: String
    let displayTypeLabel: String
    let displayTypeRawValue: String
    let projectLocaleLabel: String
    let projectLocaleCode: String
    let appStoreLocaleCode: String?
    let templateCount: Int
    let isSelected: Bool
    let skipReason: String?

    var screenshotCount: Int { isSelected ? templateCount : 0 }
}

/// One per source row: the row/display-type details are constant across locales, so they're
/// shown once in the group header and the varying locale destinations are listed beneath.
struct ASCUploadRowGroup: Identifiable {
    let id: String
    let destinationLabel: String
    let destinationPlatform: ASCPlatform?
    let rowLabel: String
    let sourceSizeLabel: String
    let displayTypeLabel: String
    let displayTypeRawValue: String
    let templateCount: Int
    let entries: [ASCUploadPlanEntry]

    var screenshotCount: Int { entries.reduce(0) { $0 + $1.screenshotCount } }
}
