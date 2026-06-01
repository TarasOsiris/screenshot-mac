import Foundation
import SwiftUI

/// Cross-platform constants and helpers shared by the macOS and iPad Settings surfaces,
/// so the two don't drift.
enum AppLinks {
    static let privacy = URL(string: "https://screenshotbro.app/privacy")!
    static let terms = URL(string: "https://screenshotbro.app/terms")!
}

/// Interface-language override (persisted via the `AppleLanguages` default).
enum AppLanguageOptions {
    /// Bundled UI languages, minus the "Base" pseudo-localization, sorted by code.
    static var available: [String] {
        Bundle.main.localizations.filter { $0 != "Base" }.sorted()
    }

    /// The language's own endonym (e.g. "Deutsch" for `de`).
    static func displayName(for code: String) -> String {
        let locale = Locale(identifier: code)
        if let name = locale.localizedString(forLanguageCode: code) {
            return name.capitalized(with: locale)
        }
        return code
    }

    /// Persists the override (empty string = follow the system language). Takes effect on relaunch.
    static func apply(_ code: String) {
        if code.isEmpty {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
    }
}

/// A third-party asset credit shown in Settings → Attributions on both platforms.
struct AppAttribution: Identifiable {
    enum Category: String, CaseIterable, Identifiable {
        case models
        case templates
        case svg

        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .models: "3D Models"
            case .templates: "Templates"
            case .svg: "SVG Presets"
            }
        }
    }

    let id = UUID()
    let category: Category
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let license: LocalizedStringKey?
    let linkTitle: LocalizedStringKey
    let url: URL

    static let all: [AppAttribution] = [
        AppAttribution(
            category: .models,
            title: "iPhone 17 Pro",
            subtitle: "by Ibrahim.Bhl",
            license: "License: CC Attribution",
            linkTitle: "View on Sketchfab",
            url: URL(string: "https://sketchfab.com/3d-models/iphone-17-pro-4aeeeb41f9d14f96bb3f2589edc3edac")!
        ),
        AppAttribution(
            category: .models,
            title: "iPhone 17 Pro Max",
            subtitle: "by izatrcsldssb",
            license: "License: CC Attribution",
            linkTitle: "View on Sketchfab",
            url: URL(string: "https://sketchfab.com/3d-models/iphone-17-pro-max-d24511d4d7534a4b89efdcf8fb6fae88")!
        ),
        AppAttribution(
            category: .templates,
            title: "500 App Store Screenshot Templates",
            subtitle: "for Android and iOS Apps",
            license: nil,
            linkTitle: "View on Figma Community",
            url: URL(string: "https://www.figma.com/community/file/1471925742378558731/500-app-store-screenshot-templates-for-android-and-ios-apps")!
        ),
        AppAttribution(
            category: .svg,
            title: "Shapes Gallery",
            subtitle: "Free SVG shapes bundled as presets in the SVG picker",
            license: nil,
            linkTitle: "shapes.gallery",
            url: URL(string: "https://www.shapes.gallery/")!
        ),
    ]

    static func inCategory(_ category: Category) -> [AppAttribution] {
        all.filter { $0.category == category }
    }
}
