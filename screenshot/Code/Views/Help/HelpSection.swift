import SwiftUI

#if os(macOS)
enum HelpSection: String, CaseIterable, Identifiable, Hashable {
    case welcome
    case projects
    case rows
    case templates
    case shapes
    case devices
    case backgrounds
    case editing
    case locales
    case importing
    case exporting
    case showcase
    case appStoreConnect
    case googlePlay
    case iCloud
    case automation
    case settings
    case proFeatures
    case shortcuts
    case tips
    case support

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .welcome: "Welcome"
        case .projects: "Projects"
        case .rows: "Rows"
        case .templates: "Templates"
        case .shapes: "Shapes & Text"
        case .devices: "Devices & Frames"
        case .backgrounds: "Backgrounds"
        case .editing: "Editing on the Canvas"
        case .locales: "Languages & Translations"
        case .importing: "Importing"
        case .exporting: "Exporting"
        case .showcase: "Showcase Export"
        case .appStoreConnect: "App Store Connect"
        case .googlePlay: "Google Play"
        case .iCloud: "iCloud Sync"
        case .automation: "Automation & MCP"
        case .settings: "Settings & Defaults"
        case .proFeatures: "Free vs Pro"
        case .shortcuts: "Keyboard Shortcuts"
        case .tips: "Tips & Tricks"
        case .support: "Support & Feedback"
        }
    }

    var icon: String {
        switch self {
        case .welcome: "sparkles"
        case .projects: "folder"
        case .rows: "rectangle.stack"
        case .templates: "rectangle.split.3x1"
        case .shapes: "square.on.circle"
        case .devices: "iphone"
        case .backgrounds: "paintpalette"
        case .editing: "hand.draw"
        case .locales: "globe"
        case .importing: "square.and.arrow.down"
        case .exporting: "square.and.arrow.up"
        case .showcase: "photo.stack"
        case .appStoreConnect: "arrow.up.circle"
        case .googlePlay: "play.rectangle.on.rectangle"
        case .iCloud: "icloud"
        case .automation: "terminal"
        case .settings: "gear"
        case .proFeatures: "star"
        case .shortcuts: "keyboard"
        case .tips: "lightbulb"
        case .support: "questionmark.circle"
        }
    }
}
#endif
