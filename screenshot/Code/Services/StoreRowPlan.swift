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
nonisolated struct StoreRowPlan<AssetType, LocaleTarget: Identifiable>: Identifiable {
    let id: UUID
    var rowLabel: String
    var rowSize: CGSize
    var templateCount: Int
    var isEnabled: Bool
    var detectedAssetType: AssetType
    var selectedAssetType: AssetType
    var localeTargets: [LocaleTarget]
    var inferredStorePlatform: StorePlatform?
}
