import SwiftUI

#if os(macOS)
extension EnvironmentValues {
    /// The active search needle, pre-trimmed. Threading it as a parameter meant every Help
    /// component grew a stored property, an init argument, and a forwarding call at each parent.
    @Entry var helpSearchQuery = ""
    /// Set by `HelpView` so a "See also" link can change the selected topic without the block
    /// renderers couriering a closure down to it.
    @Entry var openHelpSection: (HelpSection) -> Void = { _ in }
}

/// Every Help block renders the same way: resolve, parse markdown, highlight the search match.
struct HelpText: View {
    let resource: LocalizedStringResource
    @Environment(\.helpSearchQuery) private var query

    init(_ resource: LocalizedStringResource) { self.resource = resource }

    var body: some View {
        Text(resource.helpMarkdown.helpHighlighting(query))
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension LocalizedStringResource {
    var helpResolved: String { String(localized: self) }

    /// Resolved first, then parsed — *not* fed back through `LocalizedStringKey`, because a short
    /// translated string can collide with another catalog key and get translated a second time.
    var helpMarkdown: AttributedString {
        let text = helpResolved
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

extension AttributedString {
    /// `needle` is already trimmed — `HelpView` owns that, so this isn't re-done per rendered block.
    func helpHighlighting(_ needle: String) -> AttributedString {
        guard !needle.isEmpty else { return self }
        var result = self
        var cursor = result.startIndex
        while let match = result[cursor...].range(
            of: needle,
            options: HelpSearch.options,
            locale: .current
        ) {
            result[match].backgroundColor = .yellow.opacity(HelpSearch.highlightOpacity)
            cursor = match.upperBound
        }
        return result
    }
}

enum HelpSearch {
    static let highlightOpacity: Double = 0.35

    /// Matches `localizedStandardContains`, which `LocalePresetsSheet` already settled on: plain
    /// `.caseInsensitive` folds Turkish dotted/dotless I wrongly for a tr-locale user, and the two
    /// search surfaces must fold the same way as the highlighter below.
    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    static func matches(_ haystack: String, _ needle: String) -> Bool {
        needle.isEmpty || haystack.localizedStandardContains(needle)
    }
}
#endif
