import SwiftUI

/// What the app is doing between a project being asked for and its editor being usable.
///
/// Two things make this a phase machine rather than the `Bool` it replaced: the overlay can say
/// which step is running, and `showsEditorContent` opens one phase *before* the overlay drops —
/// so the incoming project's first (expensive) layout happens while the spinner is still
/// committed to the render server instead of behind a frozen window.
@MainActor
@Observable
final class ProjectOpenProgress {
    enum Phase: Equatable, CaseIterable {
        case idle
        case preparing
        case reading
        case fonts
        case building
    }

    private(set) var phase: Phase = .idle
    private(set) var projectName: String?
    private(set) var isRemote = false
    private(set) var imagesLoaded = 0
    private(set) var imagesTotal = 0

    /// Give SwiftUI a frame to commit the current state before the next main-actor stall, so the
    /// spinner is already on the render server and keeps animating through it. There is no API to
    /// await a committed frame, so this is a sleep; every caller goes through it by name.
    static func awaitPaint() async {
        try? await Task.sleep(for: .milliseconds(50))
    }

    /// Below this the decode is over before the eye registers it, so an indicator would only flash.
    private static let imageIndicatorMinimum = 8

    var isOpening: Bool { phase != .idle }

    /// The editor's rows render from `.building` on; every earlier phase keeps them out of the
    /// tree so the project-id change tears down a subtree instead of rebuilding the outgoing
    /// project's canvases behind the overlay.
    var showsEditorContent: Bool { phase == .idle || phase == .building }

    var isLoadingImages: Bool { imagesTotal >= Self.imageIndicatorMinimum && imagesLoaded < imagesTotal }

    var title: LocalizedStringKey {
        guard let projectName, !projectName.isEmpty else { return "Opening Project…" }
        return "Opening “\(projectName)”"
    }

    var detail: LocalizedStringKey? {
        switch phase {
        case .idle: return nil
        case .preparing: return "Preparing…"
        case .reading: return isRemote ? "Downloading from iCloud…" : "Opening the project file…"
        case .fonts: return "Loading fonts…"
        case .building: return "Preparing the editor…"
        }
    }

    func begin(projectName: String?, isRemote: Bool) {
        self.projectName = projectName
        self.isRemote = isRemote
        phase = .preparing
        imagesLoaded = 0
        imagesTotal = 0
    }

    /// No-ops once finished, so a superseded open's remaining steps can't re-raise the overlay.
    func advance(to phase: Phase) {
        guard self.phase != .idle else { return }
        self.phase = phase
    }

    func finish() {
        phase = .idle
    }

    func beginImages(total: Int) {
        imagesTotal = max(0, total)
        imagesLoaded = 0
    }

    func advanceImages(to loaded: Int) {
        imagesLoaded = min(max(0, loaded), imagesTotal)
    }

    func finishImages() {
        imagesLoaded = 0
        imagesTotal = 0
    }
}
