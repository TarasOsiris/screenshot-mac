import SwiftUI

/// Single source of truth for onboarding-related UserDefaults keys.
/// Reach for these constants instead of bare string literals so a rename
/// or future migration can be done in one place.
enum OnboardingPersistence {
    static let completedKey = "onboardingCompleted"
    /// iPad defers the editor coach tour until the first project opens, which can be a
    /// different launch than the welcome flow — so the pending state must survive restarts.
    static let editorCoachPendingKey = "editorCoachPending"
    private static let forceOnboardingEnvironmentKey = "SCREENSHOT_FORCE_ONBOARDING"

    static func prepareForLaunch() {
        if isForceOnboardingEnabled {
            UserDefaults.standard.set(false, forKey: completedKey)
            UserDefaults.standard.removeObject(forKey: editorCoachPendingKey)
            return
        }
        guard launchOnboardingDisabledOnCurrentDevice else { return }
        // iPad skips the welcome cover but still gets the editor tour — arm the
        // deferred coach once, on first launch, before marking onboarding done.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: completedKey) {
            defaults.set(true, forKey: editorCoachPendingKey)
        }
        defaults.set(true, forKey: completedKey)
    }

    static var isEditorCoachPending: Bool {
        UserDefaults.standard.bool(forKey: editorCoachPendingKey)
    }

    static func setEditorCoachPending() {
        UserDefaults.standard.set(true, forKey: editorCoachPendingKey)
    }

    static func clearEditorCoachPending() {
        UserDefaults.standard.removeObject(forKey: editorCoachPendingKey)
    }

    // Cached: the env var and device idiom can't change mid-process, and the
    // iOS welcome-cover binding re-reads this on every root body pass.
    static let launchOnboardingDisabledOnCurrentDevice: Bool = {
        guard !isForceOnboardingEnabled else { return false }
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }()

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
    case shapes
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
        case .inspector: "Style your row"
        case .shapes: "Add text & shapes"
        case .locale: "Localize your screenshots"
        case .export: "Export when ready"
        case .pro: "Unlock everything with Pro"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .canvas:
            #if os(macOS)
            "Drag screenshots from Finder onto a canvas, or drop several at once to fill the row."
            #else
            "Double-tap the device to pick a screenshot from Photos or Files."
            #endif
        case .inspector:
            "Use the inspector on the right to set the background, default device frame, and screenshot size."
        case .shapes:
            "Add text, images, devices, and shapes from here. They'll appear on the selected row."
        case .locale:
            #if os(macOS)
            "Add languages to translate every text layer at once. Cmd+] cycles between them."
            #else
            "Add languages to translate every text layer at once."
            #endif
        case .export:
            "Export every row in every language as PNG or JPEG, ready to upload to App Store Connect or Google Play."
        case .pro:
            "Free covers one project. Upgrade here anytime to unlock unlimited projects, rows, and templates."
        }
    }

    var icon: String {
        switch self {
        case .canvas: "square.and.arrow.down.on.square"
        case .inspector: "sidebar.right"
        case .shapes: "plus.rectangle.on.rectangle"
        case .locale: "globe"
        case .export: "square.and.arrow.up"
        case .pro: "crown"
        }
    }

    var accentColor: Color {
        switch self {
        case .canvas: .blue
        case .inspector: .orange
        case .shapes: .purple
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
