import Foundation

/// Editor presentation that must be single across the whole editor rather than per row or per
/// template.
///
/// Session state, not document state, so it lives on `AppState` as a sub-controller rather than in
/// the undo/save snapshot — the same arrangement as `zoom`, `viewMode` and `localeMenu`.
@Observable
final class EditorPresentation {
    /// The one template whose background-override popover is open. A `@State` flag per
    /// `TemplateControlBar` let two popovers stand at once, and scoping it to the row only stopped
    /// that within a row — the popovers are `interactiveDismissDisabled`, so nothing light-dismisses
    /// the one in the row you just left.
    var backgroundPopoverTemplateId: UUID?
}
