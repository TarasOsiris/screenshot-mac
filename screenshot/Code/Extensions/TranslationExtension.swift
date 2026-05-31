import OSLog
import SwiftUI
import Translation

extension Optional where Wrapped == TranslationSession.Configuration {
    /// Creates or re-triggers a configuration for the language pair.
    /// First call creates a new config; subsequent calls invalidate the existing
    /// tracked config so `.translationTask` re-fires reliably.
    mutating func refresh(source: String, target: String) {
        let newSource = Locale.Language(identifier: source)
        let newTarget = Locale.Language(identifier: target)
        if let existing = self, existing.source == newSource, existing.target == newTarget {
            // Same language pair — invalidate in-place so .translationTask re-fires.
            // Creating a new config doesn't work: SwiftUI treats same-source/target as equal.
            self?.invalidate()
        } else {
            self = .init(source: newSource, target: newTarget)
        }
    }
}

/// Whether a translation item's override text is empty (i.e. not yet translated).
func isUntranslated(_ overrideText: String?) -> Bool {
    (overrideText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

/// Translate text shapes for a specific locale using a caller-provided translation function.
/// Returns `true` if all shapes translated successfully, `false` if translation was interrupted by an error.
@discardableResult
func translateShapes(
    state: AppState,
    targetLocaleCode: String,
    onlyUntranslated: Bool = true,
    shapeFilter: ((UUID) -> Bool)? = nil,
    translate: @escaping (String) async throws -> String
) async -> Bool {
    let items = state.textShapesForTranslation(localeCode: targetLocaleCode)
    for item in items {
        if let filter = shapeFilter, !filter(item.shape.id) { continue }
        if onlyUntranslated && !isUntranslated(item.overrideText) { continue }
        guard let baseText = item.shape.text, !baseText.isEmpty else { continue }
        do {
            let translatedText = try await translatePreservingLineBreaks(baseText, translate: translate)
            state.updateTranslationText(
                shapeId: item.shape.id,
                localeCode: targetLocaleCode,
                text: translatedText
            )
        } catch {
            AppLogger.translation.error("Translation failed for shape \(item.shape.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            // Stop the entire loop on first failure — avoids re-showing
            // the language download dialog for every remaining shape.
            return false
        }
    }
    return true
}

/// Thin wrapper that translates via the given session. Delegates to the primary overload.
@discardableResult
func translateShapes(
    session: TranslationSession,
    state: AppState,
    targetLocaleCode: String,
    onlyUntranslated: Bool = true,
    shapeFilter: ((UUID) -> Bool)? = nil
) async -> Bool {
    await translateShapes(
        state: state,
        targetLocaleCode: targetLocaleCode,
        onlyUntranslated: onlyUntranslated,
        shapeFilter: shapeFilter
    ) { baseText in
        let response = try await session.translate(baseText)
        return response.targetText
    }
}

/// Translate the full text in one request while protecting the original newline
/// separators. This keeps sentence context across lines, but prevents Apple's
/// translation session from adding padding around explicit newlines.
func translatePreservingLineBreaks(
    _ text: String,
    translate: @escaping (String) async throws -> String
) async throws -> String {
    guard text.contains(where: \.isNewline) else {
        return try await translate(text)
    }

    let protected = protectLineBreaks(in: text)
    let translated = try await translate(protected.text)
    return restoringLineBreaks(in: translated, breaks: protected.breaks)
}

private struct ProtectedLineBreak {
    let token: String
    let separator: String
    let beforePadding: String
    let afterPadding: String
}

private func protectLineBreaks(in text: String) -> (text: String, breaks: [ProtectedLineBreak]) {
    var protected = ""
    var breaks: [ProtectedLineBreak] = []
    var index = text.startIndex
    var lastAppendWasLineBreakToken = false

    while index < text.endIndex {
        let character = text[index]
        guard character.isNewline else {
            protected.append(character)
            lastAppendWasLineBreakToken = false
            index = text.index(after: index)
            continue
        }

        let token = lineBreakToken(at: breaks.count)
        let beforePadding: String
        if lastAppendWasLineBreakToken {
            beforePadding = ""
        } else {
            beforePadding = protected.removingTrailingHorizontalWhitespace()
        }
        let nextIndex = text.index(after: index)
        var separator: String
        var afterLineBreakIndex: String.Index
        if character == "\r", nextIndex < text.endIndex, text[nextIndex] == "\n" {
            separator = "\r\n"
            afterLineBreakIndex = text.index(after: nextIndex)
        } else {
            separator = String(character)
            afterLineBreakIndex = nextIndex
        }

        var afterPadding = ""
        while afterLineBreakIndex < text.endIndex, text[afterLineBreakIndex].isHorizontalWhitespace {
            afterPadding.append(text[afterLineBreakIndex])
            afterLineBreakIndex = text.index(after: afterLineBreakIndex)
        }

        breaks.append(ProtectedLineBreak(
            token: token,
            separator: separator,
            beforePadding: beforePadding,
            afterPadding: afterPadding
        ))
        protected += " \(token) "
        lastAppendWasLineBreakToken = true
        index = afterLineBreakIndex
    }

    return (protected, breaks)
}

private func restoringLineBreaks(in text: String, breaks: [ProtectedLineBreak]) -> String {
    var restored = text

    for lineBreak in breaks {
        guard let tokenRange = restored.range(of: lineBreak.token) else {
            // The translator mangled or dropped the sentinel, so we can no longer
            // tell where the newline went. Log it (diagnosable) and skip — better
            // than leaking a stray token into user-visible text.
            AppLogger.translation.error("Line-break sentinel did not survive translation; newline could not be restored")
            continue
        }
        let replacementRange = horizontalWhitespacePaddedRange(around: tokenRange, in: restored)
        restored.replaceSubrange(replacementRange, with: lineBreak.beforePadding + lineBreak.separator + lineBreak.afterPadding)
    }

    return restored
}

/// A line-break sentinel built from a Private Use Area scalar. A token made of
/// real words, brackets, or ASCII digits (e.g. `<<<LINE_BREAK_0>>>`) can be
/// translated, stripped, or have its digits localized by the translation engine,
/// which would drop the newline and leak garbled text into the screenshot. PUA
/// scalars carry no linguistic meaning, so Apple's translator passes them through
/// untouched. `0xE000 + index` stays inside the PUA block (U+E000–U+F8FF) for any
/// realistic number of line breaks.
private func lineBreakToken(at index: Int) -> String {
    let scalar = UnicodeScalar(0xE000 + UInt32(index)) ?? UnicodeScalar(0xE000)!
    return String(scalar)
}

private func horizontalWhitespacePaddedRange(around range: Range<String.Index>, in text: String) -> Range<String.Index> {
    var lowerBound = range.lowerBound
    while lowerBound > text.startIndex {
        let previous = text.index(before: lowerBound)
        guard text[previous].isHorizontalWhitespace else { break }
        lowerBound = previous
    }

    var upperBound = range.upperBound
    while upperBound < text.endIndex, text[upperBound].isHorizontalWhitespace {
        upperBound = text.index(after: upperBound)
    }

    return lowerBound..<upperBound
}

private extension Character {
    var isHorizontalWhitespace: Bool {
        unicodeScalars.allSatisfy { CharacterSet.whitespaces.contains($0) }
    }
}

private extension String {
    mutating func removingTrailingHorizontalWhitespace() -> String {
        var removed = ""
        while let last = self.last, last.isHorizontalWhitespace {
            removed.insert(removeLast(), at: removed.startIndex)
        }
        return removed
    }
}

// MARK: - Language Download Alert

extension View {
    func translationLanguageDownloadAlert(isPresented: Binding<Bool>) -> some View {
        self.alert("Translation Languages Not Available", isPresented: isPresented) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.SystemPreferences.TranslationSettings") {
                Button("Open System Settings") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("The required languages are not downloaded on your Mac.\n\nTo download them, go to:\nSystem Settings → General → Language & Region → Translation Languages\n\nThen download the languages you need and try again.")
        }
    }
}
