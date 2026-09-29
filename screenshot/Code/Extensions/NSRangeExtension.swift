import Foundation

nonisolated extension NSRange {
    /// Keeps a stale selection inside the text; indexing past the end raises NSRangeException (SCREENSHOT-BRO-21).
    func clamped(toLength length: Int) -> NSRange {
        let start = min(location, length)
        return NSRange(location: start, length: min(self.length, length - start))
    }

    /// This selection in `text.uppercased()`, which can change UTF-16 length ("ß" → "SS").
    func mappedThroughUppercasing(_ text: String) -> NSRange {
        let string = text as NSString
        let range = clamped(toLength: string.length)
        return NSRange(
            location: string.substring(to: range.location).uppercased().utf16.count,
            length: string.substring(with: range).uppercased().utf16.count
        )
    }
}
