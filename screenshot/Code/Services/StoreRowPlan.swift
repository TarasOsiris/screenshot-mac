import Foundation

/// One editor row's upload plan, shared by both stores.
///
/// `ASCRowPlan` and `GPRowPlan` were field-for-field identical apart from the asset-type slot,
/// down to the same header comment. `AssetType` is that slot: `ASCDisplayType?` for Apple, which
/// needs an exact size match and so can be unresolved, and `GPImageType` for Play, which accepts
/// any size in range and so always detects one.
///
/// The locale targets stay separate types — Apple's carries a user choice over a fetched list of
/// localizations, Play's is a pure function of the project locale code — so they are the second
/// parameter rather than being forced into a shared shape.
/// Which document version an upload plan was built from. A cached plan is only still valid while
/// both halves match, so services can hold this instead of reaching into `AppState` for it.
nonisolated struct DocumentStamp: Equatable {
    let projectId: UUID
    let modifiedAt: Date?
}

/// A per-row locale/language target in a store upload plan. `isToggleable` is whatever makes a
/// locale a real candidate for that store (ASC candidates, a Play language match) — a locale
/// that isn't toggleable can't be flipped on regardless of `isEnabled`.
nonisolated protocol LocaleUploadTarget: Identifiable {
    var isEnabled: Bool { get set }
    var isToggleable: Bool { get }
}

nonisolated struct StoreRowPlan<AssetType, LocaleTarget: LocaleUploadTarget>: Identifiable {
    let id: UUID
    var rowLabel: String
    var rowSize: CGSize
    var templateCount: Int
    var isEnabled: Bool
    var detectedAssetType: AssetType
    var selectedAssetType: AssetType
    var localeTargets: [LocaleTarget]
    var inferredStorePlatform: StorePlatform?

    /// Rows may be unlabelled; every plan row and upload message still needs something to call
    /// them. Distinct from `StoreUploadChecks.rowName`, which the validators use and which is
    /// deliberately unlocalized.
    var displayLabel: String {
        rowLabel.isEmpty ? String(localized: "Row") : rowLabel
    }

    var sizeLabel: String {
        "\(Int(rowSize.width))×\(Int(rowSize.height))"
    }

    /// The subtitle every row-plan card shows. Both store wizards had built this string
    /// themselves, identically.
    var sizeAndCountSummary: String {
        templateCount == 1
            ? String(localized: "\(sizeLabel) · 1 screenshot")
            : String(localized: "\(sizeLabel) · \(templateCount) screenshots")
    }

    var hasToggleableLocaleTargets: Bool {
        localeTargets.contains { $0.isToggleable }
    }

    /// Whether every toggleable locale target is enabled — the state a row-plan card's All/None
    /// button reflects and flips.
    var allToggleableLocalesEnabled: Bool {
        hasToggleableLocaleTargets && localeTargets.allSatisfy { !$0.isToggleable || $0.isEnabled }
    }

    mutating func setAllLocaleTargets(enabled: Bool) {
        for index in localeTargets.indices where localeTargets[index].isToggleable {
            localeTargets[index].isEnabled = enabled
        }
    }
}
