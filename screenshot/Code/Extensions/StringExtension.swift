import Foundation

extension String {
    /// A single-line, length-capped rendering for menu labels: collapses newlines, trims, and
    /// ellipsizes past `maxLength` so a long base string stays readable in a menu.
    func singleLineMenuLabel(maxLength: Int = 42) -> String {
        let oneLine = replacing("\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return oneLine.count > maxLength ? String(oneLine.prefix(maxLength)) + "…" : oneLine
    }

    /// Parses a number field that may hold a comma decimal separator (a locale-formatted value,
    /// or one typed on a numeric keypad) — tries the user's locale first, then falls back to `.`.
    func localeTolerantDouble() -> Double? {
        (try? Double(self, format: .number)) ?? Double(replacing(",", with: "."))
    }
}
