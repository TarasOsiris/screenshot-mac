import SwiftUI

extension Binding {
    func onSet(_ action: @escaping () -> Void) -> Binding<Value> {
        Binding(
            get: { wrappedValue },
            set: { wrappedValue = $0; action() }
        )
    }
}

extension Binding where Value == String {
    func limited(to maxLength: Int) -> Binding<String> {
        Binding<String>(
            get: { wrappedValue },
            set: { wrappedValue = String($0.prefix(maxLength)) }
        )
    }
}
