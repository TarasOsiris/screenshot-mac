import Foundation
import Observation

/// One-shot signals between the locale menu, the canvas and the toolbar.
///
/// These four were on `AppState`, but no document code reads any of them — they are a view-to-view
/// event bus that happened to be parked on the document object. `isFanOutTranslating` is the
/// clearest case: it is written only by `LocaleToolbarMenu` and read only by other views.
///
/// Each is consumed via `.onChange`, so all four must stay plainly observed and `Equatable`.
@Observable
@MainActor
final class LocaleMenuCoordinator {
    /// A menu command raised from the app menu or a toolbar button, for `LocaleToolbarMenu` to run.
    var pendingMenuRequest: LocaleMenuRequest?

    /// A single shape the canvas asked to translate.
    var pendingTranslateShapeId: UUID?

    /// A set of shapes to translate together, from the "translate all" affordances.
    var pendingFanOutTranslateShapeIds: Set<UUID>?

    /// True while a fan-out translation runs, so the affordances can show progress and disable
    /// themselves. Driven entirely by the view running the translation.
    var isFanOutTranslating = false
}
