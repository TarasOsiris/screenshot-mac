import SwiftUI

/// Single source of truth for onboarding-related UserDefaults keys.
/// Reach for these constants instead of bare string literals so a rename
/// or future migration can be done in one place.
enum OnboardingPersistence {
    static let completedKey = "onboardingCompleted"
}

/// Steps of the interactive onboarding popover series ("coach marks").
/// Order is significant — `next` advances along this sequence.
enum OnboardingCoachStep: Int, CaseIterable, Identifiable {
    case canvas
    case inspector
    case shapes
    case locale
    case export

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .canvas: "Drop a screenshot here"
        case .inspector: "Style your row"
        case .shapes: "Add text & shapes"
        case .locale: "Localize your screenshots"
        case .export: "Export when ready"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .canvas:
            "Drag screenshots from Finder onto a canvas, or drop several at once to fill the row."
        case .inspector:
            "Use the inspector on the right to set the background, default device frame, and screenshot size."
        case .shapes:
            "Add text, images, devices, and shapes from here. They'll appear on the selected row."
        case .locale:
            "Add languages to translate every text layer at once. Cmd+] cycles between them."
        case .export:
            "Export every row in every language as PNG or JPEG, ready to upload to App Store Connect or Google Play."
        }
    }

    var icon: String {
        switch self {
        case .canvas: "square.and.arrow.down.on.square"
        case .inspector: "sidebar.right"
        case .shapes: "plus.rectangle.on.rectangle"
        case .locale: "globe"
        case .export: "square.and.arrow.up"
        }
    }

    var accentColor: Color {
        switch self {
        case .canvas: .blue
        case .inspector: .orange
        case .shapes: .purple
        case .locale: .teal
        case .export: .green
        }
    }

    var stepNumber: Int { rawValue + 1 }
    static var totalSteps: Int { allCases.count }

    var next: OnboardingCoachStep? {
        OnboardingCoachStep(rawValue: rawValue + 1)
    }

    var previous: OnboardingCoachStep? {
        OnboardingCoachStep(rawValue: rawValue - 1)
    }
}
