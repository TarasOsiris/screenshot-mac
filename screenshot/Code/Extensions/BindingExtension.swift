import SwiftUI

extension Binding {
    func onSet(_ action: @escaping () -> Void) -> Binding<Value> {
        Binding(
            get: { wrappedValue },
            set: { wrappedValue = $0; action() }
        )
    }

    /// For `Binding<X?>`, exposes a `Bool` binding that is `true` when the wrapped
    /// optional is non-nil and clears the underlying value when set to `false`.
    /// Setting to `true` is a no-op. Useful for `.alert` / `.sheet` dismissal.
    func isPresent<Wrapped>() -> Binding<Bool> where Value == Wrapped? {
        Binding<Bool>(
            get: { wrappedValue != nil },
            set: { if !$0 { wrappedValue = nil } }
        )
    }
}

extension Binding where Value: SetAlgebra {
    /// A `Bool` binding for an element's membership in this set — insert on `true`,
    /// remove on `false`. Useful for driving a `Toggle` per option in a multi-select.
    func contains(_ element: Value.Element) -> Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue.contains(element) },
            set: { isOn in
                if isOn { wrappedValue.insert(element) }
                else { wrappedValue.remove(element) }
            }
        )
    }
}
