import Foundation

extension String {
    /// A single-line, length-capped rendering for menu labels: collapses newlines, trims, and
    /// ellipsizes past `maxLength` so a long base string stays readable in a menu.
    func singleLineMenuLabel(maxLength: Int = 42) -> String {
        let oneLine = replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return oneLine.count > maxLength ? String(oneLine.prefix(maxLength)) + "…" : oneLine
    }
}
