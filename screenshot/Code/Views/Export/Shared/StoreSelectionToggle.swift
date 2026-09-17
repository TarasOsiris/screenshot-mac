import SwiftUI

extension View {
    /// A row that selects an item out of a list — a locale, a language, a version. macOS draws
    /// those as checkboxes; iPad has no checkbox control, so it falls back to a small switch.
    ///
    /// Not for a row's own on/off *setting* (the Include toggle), which stays a switch on both:
    /// that one applies immediately rather than contributing to a selection.
    func storeSelectionToggleStyle() -> some View {
        #if os(macOS)
        toggleStyle(.checkbox)
        #else
        toggleStyle(.switch)
            .controlSize(.small)
        #endif
    }
}
