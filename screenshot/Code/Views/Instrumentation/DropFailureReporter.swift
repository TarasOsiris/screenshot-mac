import SwiftUI

/// A drag-and-drop that couldn't be completed. Built where the file is decoded — off the main
/// actor, inside the item provider's callback — so it carries only Sendable strings.
struct DropFailure {
    let title: String
    let message: String

    static func image(_ error: (any Error)?) -> DropFailure {
        DropFailure(title: addImageTitle, message: error.map {
            String(localized: "Couldn't read the dropped image: \($0.localizedDescription)")
        } ?? String(localized: "That file isn't a supported image."))
    }

    static func imageOrSvg(_ error: (any Error)?) -> DropFailure {
        DropFailure(title: addImageTitle, message: error.map {
            String(localized: "Couldn't read the dropped file: \($0.localizedDescription)")
        } ?? String(localized: "That file isn't a supported image or SVG."))
    }

    static func svg(_ error: (any Error)?) -> DropFailure {
        DropFailure(title: addSvgTitle, message: error.map {
            String(localized: "Couldn't read the dropped SVG: \($0.localizedDescription)")
        } ?? String(localized: "That file isn't a supported SVG."))
    }

    static var unrenderableSvg: DropFailure {
        DropFailure(title: addSvgTitle, message: String(localized: "That SVG couldn't be rendered."))
    }

    private static var addImageTitle: String { String(localized: "Couldn't Add Image") }
    private static var addSvgTitle: String { String(localized: "Couldn't Add SVG") }
}

/// Shows a `DropFailure`. Drop handling lives in reusable editors that must not reach for
/// `AppState` — `CanvasShapeView` above all, which `Rendering/` also builds for export — so the
/// app injects one reporter for the whole tree. Comparing on state identity (which never changes
/// for the life of a window) is what keeps a fresh value per `ContentView` body pass from
/// re-propagating the environment to every shape.
struct DropFailureReporter: Equatable {
    weak var state: AppState?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.state === rhs.state }

    func callAsFunction(_ failure: DropFailure) {
        state?.presentFailure(title: failure.title, message: failure.message)
    }
}

extension EnvironmentValues {
    @Entry var reportDropFailure = DropFailureReporter()
}
