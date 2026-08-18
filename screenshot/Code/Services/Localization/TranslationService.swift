import OSLog
import SwiftUI
@preconcurrency import Translation

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

/// macOS' on-device translator can silently fall back to a *different* installed language
/// when the requested pair isn't available (e.g. returning French when German isn't
/// downloaded) instead of throwing. Storing that would write the wrong language into a
/// locale's overrides, so verify the engine honored the requested target and throw
/// otherwise — which fails the run loudly and surfaces the language-download alert.
struct WrongTargetLanguageError: LocalizedError {
    let requested: String
    let returned: String
    var errorDescription: String? {
        "The translator returned \(returned) instead of the requested \(requested). The target language may not be downloaded."
    }
}

/// Returns the response's translated text, but only after confirming it is in the language
/// we asked for. Compares language code only (ignores region/script) so e.g. a "pt-BR"
/// request still accepts a "pt" response.
nonisolated func validatedTargetText(_ response: TranslationSession.Response, requestedTarget: String) throws -> String {
    let requested = Locale.Language(identifier: requestedTarget).languageCode
    let returned = response.targetLanguage.languageCode
    if let requested, let returned, requested != returned {
        AppLogger.translation.error("Translator returned \(returned.identifier, privacy: .public) for requested target \(requested.identifier, privacy: .public)")
        throw WrongTargetLanguageError(requested: requested.identifier, returned: returned.identifier)
    }
    return response.targetText
}

/// Translate text shapes for a specific locale using a caller-provided translation function.
/// Returns `true` if all shapes translated successfully, `false` if translation was interrupted by an error.
@discardableResult
@MainActor
func translateShapes(
    state: AppState,
    targetLocaleCode: String,
    onlyUntranslated: Bool = true,
    shapeFilter: ((UUID) -> Bool)? = nil,
    translate: @MainActor (String) async throws -> String
) async -> Bool {
    let items = state.textShapesForTranslation(localeCode: targetLocaleCode)
    for item in items {
        if let filter = shapeFilter, !filter(item.shape.id) { continue }
        // `isTranslated` counts plain text AND manually-formatted rich-text overrides, so
        // auto-translate-missing never clobbers the user's own translations.
        if onlyUntranslated && item.isTranslated { continue }
        // Translations always start from the base locale's text — never a non-base override.
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

/// Outcome of a session-driven translation run, so callers can show the right guidance.
enum TranslationRunResult: Equatable {
    case completed
    /// The pair is downloadable but not installed (the inline download was declined or failed).
    case languagesNotDownloaded
    /// Apple's on-device translator doesn't support this language pair at all.
    case unsupportedPair
}

/// Confirms the on-device model for `source`→`target` is ready before translating, and
/// triggers Apple's native inline download confirmation when the pair is supported but not
/// yet installed. Returns `nil` when translation may proceed, or the blocking result.
/// This guards against the engine silently substituting a different installed language.
nonisolated func ensureTranslationAvailable(
    session: TranslationSession,
    source: String,
    target: String
) async -> TranslationRunResult? {
    let status = await LanguageAvailability().status(
        from: Locale.Language(identifier: source),
        to: Locale.Language(identifier: target)
    )
    if status == .unsupported {
        AppLogger.translation.error("Translation pair \(source, privacy: .public)->\(target, privacy: .public) is unsupported")
        return .unsupportedPair
    }
    do {
        // No-op when already installed; presents the system download sheet when supported.
        try await session.prepareTranslation()
        return nil
    } catch {
        AppLogger.translation.error("prepareTranslation failed for \(source, privacy: .public)->\(target, privacy: .public): \(error.localizedDescription, privacy: .public)")
        return .languagesNotDownloaded
    }
}

/// Thin wrapper that translates via the given session. Delegates to the primary overload.
/// Source is always the base locale — terms are only ever translated from base.
nonisolated func translateShapes(
    session: TranslationSession,
    state: AppState,
    targetLocaleCode: String,
    onlyUntranslated: Bool = true,
    shapeFilter: (@Sendable (UUID) -> Bool)? = nil
) async -> TranslationRunResult {
    let sourceCode = await MainActor.run {
        state.localeState.baseLocaleCode
    }
    if let blocked = await ensureTranslationAvailable(
        session: session,
        source: sourceCode,
        target: targetLocaleCode
    ) {
        return blocked
    }

    let items = await MainActor.run {
        state.textShapesForTranslation(localeCode: targetLocaleCode).map { item in
            TranslationWorkItem(
                shapeId: item.shape.id,
                baseText: item.shape.text,
                isTranslated: item.isTranslated
            )
        }
    }

    for item in items {
        if let shapeFilter, !shapeFilter(item.shapeId) { continue }
        if onlyUntranslated && item.isTranslated { continue }
        guard let baseText = item.baseText, !baseText.isEmpty else { continue }
        do {
            let translatedText = try await translatePreservingLineBreaks(
                baseText,
                session: session,
                requestedTarget: targetLocaleCode
            )
            await MainActor.run {
                state.updateTranslationText(
                    shapeId: item.shapeId,
                    localeCode: targetLocaleCode,
                    text: translatedText
                )
            }
        } catch {
            AppLogger.translation.error("Translation failed for shape \(item.shapeId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .languagesNotDownloaded
        }
    }
    return .completed
}

private nonisolated struct TranslationWorkItem: Sendable {
    let shapeId: UUID
    let baseText: String?
    let isTranslated: Bool
}

nonisolated func translatePreservingLineBreaks(
    _ text: String,
    session: TranslationSession,
    requestedTarget: String
) async throws -> String {
    guard text.contains(where: \.isNewline) else {
        return try await translateWithValidatedTarget(
            text,
            session: session,
            requestedTarget: requestedTarget
        )
    }

    let protected = protectLineBreaks(in: text)
    let translated = try await translateWithValidatedTarget(
        protected.text,
        session: session,
        requestedTarget: requestedTarget
    )
    return restoringLineBreaks(in: translated, breaks: protected.breaks)
}

private nonisolated func translateWithValidatedTarget(
    _ text: String,
    session: TranslationSession,
    requestedTarget: String
) async throws -> String {
    let response = try await session.translate(text)
    return try validatedTargetText(response, requestedTarget: requestedTarget)
}

/// Translate the full text in one request while protecting the original newline
/// separators. This keeps sentence context across lines, but prevents Apple's
/// translation session from adding padding around explicit newlines.
@MainActor
func translatePreservingLineBreaks(
    _ text: String,
    translate: @MainActor (String) async throws -> String
) async throws -> String {
    guard text.contains(where: \.isNewline) else {
        return try await translate(text)
    }

    let protected = protectLineBreaks(in: text)
    let translated = try await translate(protected.text)
    return restoringLineBreaks(in: translated, breaks: protected.breaks)
}

private nonisolated struct ProtectedLineBreak {
    let token: String
    let separator: String
    let beforePadding: String
    let afterPadding: String
}

private nonisolated func protectLineBreaks(in text: String) -> (text: String, breaks: [ProtectedLineBreak]) {
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

private nonisolated func restoringLineBreaks(in text: String, breaks: [ProtectedLineBreak]) -> String {
    var restored = text

    for lineBreak in breaks {
        guard let tokenRange = restored.range(of: lineBreak.token) else {
            // Sentinel mangled/dropped by the translator — skip rather than leak it.
            AppLogger.translation.error("Line-break sentinel did not survive translation; newline could not be restored")
            continue
        }
        let replacementRange = horizontalWhitespacePaddedRange(around: tokenRange, in: restored)
        restored.replaceSubrange(replacementRange, with: lineBreak.beforePadding + lineBreak.separator + lineBreak.afterPadding)
    }

    return restored
}

/// Line-break sentinel as a Private Use Area scalar — opaque to the translation
/// engine (no words/brackets/digits to translate, strip, or localize). `0xE000 +
/// index` stays within the PUA block (U+E000–U+F8FF).
private nonisolated func lineBreakToken(at index: Int) -> String {
    let scalar = UnicodeScalar(0xE000 + UInt32(index)) ?? UnicodeScalar(0xE000)!
    return String(scalar)
}

private nonisolated func horizontalWhitespacePaddedRange(around range: Range<String.Index>, in text: String) -> Range<String.Index> {
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

private nonisolated extension Character {
    var isHorizontalWhitespace: Bool {
        unicodeScalars.allSatisfy { CharacterSet.whitespaces.contains($0) }
    }
}

private nonisolated extension String {
    mutating func removingTrailingHorizontalWhitespace() -> String {
        var removed = ""
        while let last = self.last, last.isHorizontalWhitespace {
            removed.insert(removeLast(), at: removed.startIndex)
        }
        return removed
    }
}

// MARK: - Language Issue Alert

/// A translation that couldn't run because the on-device model for a specific language
/// is missing or unsupported. Carries the human-readable language name so the alert can
/// tell the user exactly what's wrong and what to do.
enum TranslationLanguageIssue: Identifiable, Equatable {
    case notDownloaded(language: String)
    case unsupported(language: String)

    var id: String {
        switch self {
        case .notDownloaded(let l): return "nd:\(l)"
        case .unsupported(let l): return "un:\(l)"
        }
    }

    /// Build the issue for a run result, or `nil` when the run succeeded.
    init?(_ result: TranslationRunResult, language: String) {
        switch result {
        case .completed: return nil
        case .languagesNotDownloaded: self = .notDownloaded(language: language)
        case .unsupportedPair: self = .unsupported(language: language)
        }
    }

    var title: String {
        switch self {
        case .notDownloaded(let l): return "Download \(l) to Translate"
        case .unsupported(let l): return "\(l) Isn't Available for Translation"
        }
    }

    var message: String {
        switch self {
        case .notDownloaded(let l):
            return "\(l) needs to be downloaded before it can be used for on-device translation.\n\nOpen System Settings → General → Language & Region → Translation Languages, download \(l), then try again. Until then your text stays in the base language."
        case .unsupported(let l):
            return "Apple's on-device translator can't translate your base language into \(l).\n\nYou can still type \(l) text yourself in Edit Translations — leave a field empty to fall back to the base language."
        }
    }

    /// Only the not-downloaded case is fixable via System Settings.
    var offersSettings: Bool {
        if case .notDownloaded = self { return true }
        return false
    }
}

extension View {
    func translationLanguageIssueAlert(item: Binding<TranslationLanguageIssue?>) -> some View {
        let isPresented = Binding(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        )
        return alert(
            item.wrappedValue?.title ?? "",
            isPresented: isPresented,
            presenting: item.wrappedValue
        ) { issue in
            #if os(macOS)
            if issue.offersSettings, let url = URL(string: "x-apple.systempreferences:com.apple.SystemPreferences.TranslationSettings") {
                Button("Open Translation Settings") {
                    NSWorkspace.shared.open(url)
                }
            }
            #endif
            Button("OK", role: .cancel) {}
        } message: { issue in
            Text(issue.message)
        }
    }
}
