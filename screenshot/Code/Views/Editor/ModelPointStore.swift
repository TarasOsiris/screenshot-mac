import Foundation

/// Reference box for the model-space point a context menu was opened at, so the menu's
/// actions can place a new shape where the click happened.
final class ModelPointStore {
    var value: CGPoint?
}
