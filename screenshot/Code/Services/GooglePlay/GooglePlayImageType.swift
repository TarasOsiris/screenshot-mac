import Foundation
import CoreGraphics

/// Google Play store-listing image types the app uploads screenshots to.
/// Unlike App Store Connect's exact-pixel display types, Play accepts any size within
/// broad bounds, so the picker is a free choice rather than a size match.
nonisolated enum GPImageType: String, CaseIterable, Identifiable {
    case phoneScreenshots
    case sevenInchScreenshots
    case tenInchScreenshots

    var id: String { rawValue }

    /// Path segment used in the Android Publisher `edits.images` endpoints.
    var apiValue: String { rawValue }

    var label: String {
        switch self {
        case .phoneScreenshots: return "Phone"
        case .sevenInchScreenshots: return "7-inch tablet"
        case .tenInchScreenshots: return "10-inch tablet"
        }
    }

    static let userSelectableCases: [GPImageType] = [
        .phoneScreenshots, .sevenInchScreenshots, .tenInchScreenshots
    ]

    var requirementsDescription: String {
        String(localized: "PNG or JPEG, 320–3840 px per edge, aspect ratio up to 2:1, 2–8 images.")
    }

    /// Play's screenshot rules: each edge 320–3840 px and the long edge at most twice the short edge.
    static func accepts(width: CGFloat, height: CGFloat) -> Bool {
        let w = Int(width.rounded())
        let h = Int(height.rounded())
        guard w >= minEdge, h >= minEdge, w <= maxEdge, h <= maxEdge else { return false }
        let longEdge = max(w, h)
        let shortEdge = min(w, h)
        guard shortEdge > 0 else { return false }
        return longEdge <= shortEdge * 2
    }

    /// Heuristic to pre-select the picker: portrait/tall → phone; larger or squarer → 10-inch.
    /// This is only a default — the user can always override.
    static func detect(width: CGFloat, height: CGFloat) -> GPImageType {
        let longEdge = max(width, height)
        let shortEdge = min(width, height)
        guard shortEdge > 0 else { return .phoneScreenshots }
        let aspect = longEdge / shortEdge
        // Tablet listings tend to be squarer (closer to 4:3) and larger than phones.
        if aspect < 1.5 && longEdge >= 2000 { return .tenInchScreenshots }
        if aspect < 1.5 { return .sevenInchScreenshots }
        return .phoneScreenshots
    }

    static let minEdge = 320
    static let maxEdge = 3840
}

// Per Google Play listing requirements: 2–8 screenshots per type.
nonisolated enum GPUploadLimits {
    static let minScreenshotsPerType = 2
    static let maxScreenshotsPerType = 8
}
