import Foundation

/// Picks the version string to offer when creating the next App Store version. App Store Connect
/// requires a value strictly greater than the app's current one, so the wizard suggests a bump of
/// the highest existing version rather than making the user remember what shipped.
nonisolated enum ASCVersionNumber {
    /// The highest of `versions`, compared the way the store orders releases — numerically per
    /// component, so 4.10 outranks 4.9.
    static func highest(of versions: [String]) -> String? {
        versions.max { $0.compare($1, options: .numeric) == .orderedAscending }
    }

    /// `4.14` → `4.15`, `1.2.3` → `1.2.4`, `4` → `5`. Nil when the string isn't the dotted numeric
    /// form Apple accepts, because a guess built from something unparseable would be rejected.
    static func next(after version: String) -> String? {
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.count <= 3 else { return nil }
        var numbers: [Int] = []
        for component in components {
            guard let number = Int(component), number >= 0 else { return nil }
            numbers.append(number)
        }
        numbers[numbers.count - 1] += 1
        return numbers.map(String.init).joined(separator: ".")
    }
}
