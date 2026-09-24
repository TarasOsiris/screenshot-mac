import SwiftUI

#if os(iOS)
/// iPad variant of the per-text localization popover: `barPopover` presents it as a
/// detent sheet, so the content is a native inset-grouped list (like the iPad
/// Translation Table) instead of the dense desktop column — base text up top,
/// one editable row per language with swipe-to-reset, then reuse/reset/table actions.
struct TextLocalizationSheetContent: View {
    let state: AppState
    let shapeId: UUID
    /// Locale-resolved shape from the bar, used only if the base shape lookup fails.
    let fallbackShape: CanvasShapeModel
    // Opening the Translation Table / Manage Languages from here is deferred to
    // onDisappear: LocaleBar can't present its sheet while this one is still dismissing.
    @State private var followUp: LocaleMenuRequest?
    @Environment(\.dismiss) private var dismiss

    private var baseShape: CanvasShapeModel {
        for row in state.rows {
            if let shape = row.shapes.first(where: { $0.id == shapeId }) { return shape }
        }
        return fallbackShape
    }

    var body: some View {
        let baseShape = baseShape
        let baseText = baseShape.text ?? ""
        let hasBaseText = !baseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        List {
            Section {
                if state.localeState.isBaseLocale {
                    Button {
                        state.localeMenu.pendingFanOutTranslateShapeIds = [shapeId]
                    } label: {
                        HStack(spacing: 8) {
                            if state.localeMenu.isFanOutTranslating {
                                ProgressView().controlSize(.small)
                                Text("Translating…")
                            } else {
                                Image(systemName: "character.bubble")
                                Text("Translate into All Languages (\(state.localeState.nonBaseLocaleCount))")
                            }
                        }
                    }
                    .disabled(state.localeMenu.isFanOutTranslating || !hasBaseText)
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.localeState.baseLocaleLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                    Text(hasBaseText ? baseText : String(localized: "Untitled text"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(hasBaseText ? Color.primary : Color.secondary)
                        .lineLimit(3)
                        .textCase(nil)
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(state.localeState.locales.dropFirst()) { locale in
                    translationRow(baseShape: baseShape, locale: locale)
                }
            }

            Section {
                reuseTranslationMenuContent(
                    isLinked: baseShape.translationKey != nil,
                    hasTargets: state.hasReusableTranslationTargets(excludingShapeId: shapeId),
                    targets: {
                        state.reusableTranslationTargets(excludingShapeId: shapeId)
                            .map { (key: $0.key, label: $0.baseText.singleLineMenuLabel()) }
                    },
                    onLink: { state.linkTranslation(shapeId: shapeId, toTargetKey: $0) },
                    onUnlink: { state.unlinkTranslation(shapeId: shapeId) }
                )

                // Resets every language at once, so keep it on the base locale; per-language
                // reset is the swipe action on each row above.
                if state.localeState.isBaseLocale {
                    Button(role: .destructive) {
                        state.resetAllTranslations(shapeIds: [shapeId])
                    } label: {
                        Label("Reset All Translations", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(!state.anyTranslationOrOverride(shapeIds: [shapeId]))
                }
            }

            Section {
                Button("Edit Translation Table...") {
                    followUp = .editTranslations
                    dismiss()
                }
                Button("Manage Languages...") {
                    followUp = .manageLocales
                    dismiss()
                }
            }
        }
        .listStyle(.insetGrouped)
        .onDisappear {
            if let followUp { state.localeMenu.pendingMenuRequest = followUp }
        }
    }

    @ViewBuilder
    private func translationRow(baseShape: CanvasShapeModel, locale: LocaleDefinition) -> some View {
        let override = state.translationOverrideForDisplay(shape: baseShape, localeCode: locale.code)
        let formatted = formattedTranslationPlainText(for: override)
        let hasOverride = override?.hasTextContent == true

        VStack(alignment: .leading, spacing: 6) {
            Text(locale.flagLabel)
                .font(.subheadline.weight(.semibold))

            if let formatted {
                Text(formatted.isEmpty ? String(localized: "Same as base language") : formatted)
                    .font(.body)
                    .foregroundStyle(formatted.isEmpty ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Label("Formatted — edit on the canvas", systemImage: "paintbrush.pointed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                BufferedTranslationField(
                    placeholder: String(localized: "Same as base language"),
                    text: localeTranslationBinding(state, shape: baseShape, localeCode: locale.code)
                )
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if hasOverride {
                Button(role: .destructive) {
                    state.resetTranslationText(shapeId: baseShape.id, localeCode: locale.code)
                } label: {
                    Label("Reset", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }
}
#endif
