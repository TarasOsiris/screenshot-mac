import SwiftUI

/// Single source of truth for onboarding-related UserDefaults keys.
/// Reach for these constants instead of bare string literals so a rename
/// or future migration can be done in one place.
enum OnboardingPersistence {
    static let completedKey = "onboardingCompleted"
    /// The editor coach tour is deferred until the first project's canvas appears, which
    /// can be a later launch than the first one — so the pending state must survive restarts.
    static let editorCoachPendingKey = "editorCoachPending"
    private static let forceOnboardingEnvironmentKey = "SCREENSHOT_FORCE_ONBOARDING"

    /// Arms the deferred coach tour once, on first launch, on devices that support
    /// it — or on every launch when force-onboarding is enabled.
    static func prepareForLaunch() {
        let defaults = UserDefaults.standard
        guard isForceOnboardingEnabled || !defaults.bool(forKey: completedKey) else { return }
        if OnboardingCoachStep.tourSupportedOnDevice {
            defaults.set(true, forKey: editorCoachPendingKey)
        }
        defaults.set(true, forKey: completedKey)
    }

    static var isEditorCoachPending: Bool {
        UserDefaults.standard.bool(forKey: editorCoachPendingKey)
    }

    static func clearEditorCoachPending() {
        UserDefaults.standard.removeObject(forKey: editorCoachPendingKey)
    }

    private static let isForceOnboardingEnabled: Bool = {
        guard let value = ProcessInfo.processInfo.environment[forceOnboardingEnvironmentKey] else {
            return false
        }
        return !value.isEmpty && value != "0" && value.lowercased() != "false"
    }()
}

/// Steps of the interactive onboarding popover series ("coach marks").
/// Order is significant — `next` advances along this sequence.
enum OnboardingCoachStep: Int, CaseIterable, Identifiable {
    case canvas
    case inspector
    case locale
    case export
    case pro

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .canvas:
            #if os(macOS)
            "Drop a screenshot here"
            #else
            "Add a screenshot"
            #endif
        case .inspector: "Your selected row's editor"
        case .locale: "One project, every language"
        case .export: "Export everything at once"
        case .pro: "Unlock everything with Pro"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .canvas:
            #if os(macOS)
            "Each canvas is one App Store screenshot. Drag images from Finder onto it, drop several at once to fill the whole row, or double-click the device to browse."
            #else
            "Each canvas is one App Store screenshot. Double-tap the device to pick an image from Photos or Files."
            #endif
        case .inspector:
            "This sidebar always edits the currently selected row — set its screenshot size, background, and device frame, and add text, images, and shapes from the Shapes section."
        case .locale:
            #if os(macOS)
            "Add languages from this menu and translate every text layer — by hand or automatically. Layouts stay identical in every language, and Cmd+] cycles between them."
            #else
            "Add languages from this menu and translate every text layer — by hand or automatically. Layouts stay identical in every language."
            #endif
        case .export:
            "Render every row in every language as PNG or JPEG, organized into per-language folders — or upload them straight to App Store Connect from here."
        case .pro:
            "Free includes one project with 3 rows of 5 templates each — enough to ship your first app. Upgrade here anytime for unlimited projects, rows, and templates."
        }
    }

    var icon: String {
        switch self {
        case .canvas: "square.and.arrow.down.on.square"
        case .inspector: "sidebar.right"
        case .locale: "globe"
        case .export: "square.and.arrow.up"
        case .pro: "crown"
        }
    }

    var accentColor: Color {
        switch self {
        case .canvas: .blue
        case .inspector: .orange
        case .locale: .teal
        case .export: .green
        case .pro: .yellow
        }
    }

    var stepNumber: Int { rawValue + 1 }
    static var totalSteps: Int { allCases.count }

    /// iPadOS silently drops a presentation started while another is still
    /// dismissing — pause this long before presenting the next popover or sheet.
    static let presentationSettleDelay: Duration = .milliseconds(500)

    /// The editor tour runs on macOS and iPad — iPhone's inspector is a
    /// full-screen sheet, so anchored coach marks don't translate there.
    static var tourSupportedOnDevice: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        true
        #endif
    }

    var next: OnboardingCoachStep? {
        OnboardingCoachStep(rawValue: rawValue + 1)
    }

    var previous: OnboardingCoachStep? {
        OnboardingCoachStep(rawValue: rawValue - 1)
    }
}
