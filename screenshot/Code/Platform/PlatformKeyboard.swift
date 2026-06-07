import SwiftUI

/// Platform-conditional keyboard hints for shared TextFields: iPad gets the matching
/// software keyboard; macOS compiles them away (`keyboardType` is UIKit-only).
extension View {
    /// Positive-integer fields (pixel sizes, font size, opacity %).
    @ViewBuilder
    func integerKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.numberPad)
        #else
        self
        #endif
    }

    /// Decimal fields (fractional percentages).
    @ViewBuilder
    func decimalKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    /// Numeric fields that accept a minus sign (rotation degrees) — the plain pads have no "-" key.
    @ViewBuilder
    func signedNumberKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.numbersAndPunctuation)
        #else
        self
        #endif
    }
}
