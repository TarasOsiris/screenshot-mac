import OSLog
import RegexBuilder
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
enum TranslationRunResult: String, Equatable, CaseIterable {
    case completed
    /// The pair is downloadable but not installed: `prepareTranslation()` presented the system
    /// download sheet and it did not end with the model installed — most often declined.
    ///
    /// Raw value kept from when this case meant "any failure whatsoever", so the new, narrower
    /// meaning stays comparable against the data already collected under the old one.
    case languagesNotDownloaded
    /// `prepareTranslation()` threw for a pair Apple reported as already installed — a network or
    /// session fault, not something the user can fix by downloading anything.
    case downloadFailed
    /// Apple's on-device translator doesn't support this language pair at all.
    case unsupportedPair
    /// The pair was ready and a specific shape's translation threw. Nothing to do with downloads —
    /// this used to be reported as `languagesNotDownloaded`, which is why that bucket was useless.
    case translationFailed
}

/// Confirms the on-device model for `source`→`target` is ready before translating, and
/// triggers Apple's native inline download confirmation when the pair is supported but not
/// yet installed. Returns `nil` when translation may proceed, or the blocking result.
/// This guards against the engine silently substituting a different installed language.
nonisolated(nonsending) func ensureTranslationAvailable(
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
        // Apple already told us whether the model was on disk. `.installed` failing is a session
        // or network fault the user can't fix by downloading; anything else is the download step
        // itself not completing. Collapsing the two is what made this bucket unreadable.
        return status == .installed ? .downloadFailed : .languagesNotDownloaded
    }
}

/// Thin wrapper that translates via the given session. Delegates to the primary overload.
/// Source is always the base locale — terms are only ever translated from base.
nonisolated(nonsending) func translateShapes(
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
        AnalyticsService.capture(.translationRun, [.result: blocked.rawValue, .shapeCount: 0])
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

    var translated = 0
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
            AnalyticsService.capture(.translationRun, [
                .result: TranslationRunResult.translationFailed.rawValue,
                .shapeCount: translated,
            ])
            return .translationFailed
        }
        translated += 1
    }
    AnalyticsService.capture(.translationRun, [
        .result: TranslationRunResult.completed.rawValue,
        .shapeCount: translated,
    ])
    return .completed
}

private nonisolated struct TranslationWorkItem: Sendable {
    let shapeId: UUID
    let baseText: String?
    let isTranslated: Bool
}

nonisolated(nonsending) func translatePreservingLineBreaks(
    _ text: String,
    session: TranslationSession,
    requestedTarget: String
) async throws -> String {
    try await translatePreservingLineBreaks(text) { request in
        let response = try await session.translate(request)
        return try validatedTargetText(response, requestedTarget: requestedTarget)
    }
}

/// Translates in one request, so lines keep their sentence context, with each newline swapped for
/// a sentinel the engine can't pad.
nonisolated(nonsending) func translatePreservingLineBreaks(
    _ text: String,
    translate: (String) async throws -> String
) async throws -> String {
    guard let protected = protectLineBreaks(in: text) else {
        return try await translate(text)
    }
    let translated = try await translate(protected.text)
    return restoringLineBreaks(in: translated, originals: protected.originals)
}

/// Private Use Area: opaque to the translation engine, so a sentinel is never translated or stripped.
nonisolated let lineBreakSentinelRange: ClosedRange<UInt32> = 0xE000...0xF8FF

/// nil when there is nothing to protect, or more breaks than free sentinels — translate as is.
private nonisolated func protectLineBreaks(in text: String) -> (text: String, originals: [Unicode.Scalar: String])? {
    // Icon fonts live in the Private Use Area too; never reuse a scalar the text already has.
    let used = Set(text.unicodeScalars.filter { lineBreakSentinelRange.contains($0.value) })
    var sentinels = lineBreakSentinelRange.lazy.compactMap(Unicode.Scalar.init).filter { !used.contains($0) }.makeIterator()
    var protected = ""
    var originals: [Unicode.Scalar: String] = [:]
    var cursor = text.startIndex
    for lineBreak in text.matches(of: /\h*\R\h*/) {
        guard let sentinel = sentinels.next() else { return nil }
        protected += text[cursor..<lineBreak.range.lowerBound]
        protected += " \(Character(sentinel)) "
        originals[sentinel] = String(lineBreak.output)
        cursor = lineBreak.range.upperBound
    }
    guard !originals.isEmpty else { return nil }
    protected += text[cursor...]
    return (protected, originals)
}

/// One forward pass: each sentinel, with whatever padding the engine put around it, becomes the
/// line break it replaced.
private nonisolated func restoringLineBreaks(in text: String, originals: [Unicode.Scalar: String]) -> String {
    let sentinel = Regex {
        ZeroOrMore(.horizontalWhitespace)
        Capture(CharacterClass.anyOf(originals.keys.map(Character.init)))
        ZeroOrMore(.horizontalWhitespace)
    }
    var restoredCount = 0
    let restored = text.replacing(sentinel) { match in
        restoredCount += 1
        return match.output.1.unicodeScalars.first.flatMap { originals[$0] } ?? ""
    }
    if restoredCount < originals.count {
        AppLogger.translation.error("A line-break sentinel did not survive translation; its newline could not be restored")
    }
    return restored
}

// MARK: - Language Issue Alert

/// A translation that couldn't run because the on-device model for a specific language
/// is missing or unsupported. Carries the human-readable language name so the alert can
/// tell the user exactly what's wrong and what to do.
enum TranslationLanguageIssue: Identifiable, Equatable {
    case notDownloaded(language: String)
    case unsupported(language: String)
    /// The model was installed and the run still failed — a session or network fault.
    case failed(language: String)

    var id: String {
        switch self {
        case .notDownloaded(let l): return "nd:\(l)"
        case .unsupported(let l): return "un:\(l)"
        case .failed(let l): return "fa:\(l)"
        }
    }

    /// Build the issue for a run result, or `nil` when the run succeeded.
    init?(_ result: TranslationRunResult, language: String) {
        switch result {
        case .completed: return nil
        case .languagesNotDownloaded: self = .notDownloaded(language: language)
        case .unsupportedPair: self = .unsupported(language: language)
        case .downloadFailed, .translationFailed: self = .failed(language: language)
        }
    }

    var title: String {
        switch self {
        case .notDownloaded(let l): return "Download \(l) to Translate"
        case .unsupported(let l): return "\(l) Isn't Available for Translation"
        case .failed(let l): return "Couldn't Translate into \(l)"
        }
    }

    var message: String {
        switch self {
        case .notDownloaded(let l):
            return "\(l) needs to be downloaded before it can be used for on-device translation.\n\nChoose Try Again to bring back the download prompt. Until then your text stays in the base language."
        case .unsupported(let l):
            return "Apple's on-device translator can't translate your base language into \(l).\n\nYou can still type \(l) text yourself in Edit Translations — leave a field empty to fall back to the base language."
        case .failed(let l):
            return "The translation into \(l) stopped partway.\n\nChoose Try Again to pick up where it left off — already-translated text is kept."
        }
    }

    /// Only the not-downloaded case is fixable via System Settings.
    var offersSettings: Bool {
        if case .notDownloaded = self { return true }
        return false
    }

    /// Whether re-running could plausibly succeed. Apple's own download sheet is what
    /// `prepareTranslation()` presents, so a retry *is* the download affordance — routing the
    /// user to System Settings instead was going around it.
    var offersRetry: Bool {
        if case .unsupported = self { return false }
        return true
    }
}
