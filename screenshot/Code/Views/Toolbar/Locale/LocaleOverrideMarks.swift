import SwiftUI

extension LocaleOverrideField {
    /// Deliberately "X position" rather than a bare "X": a single-letter catalog key
    /// machine-translates to a word ("Y" → "Oui"), which is why the canvas strip renders its axis
    /// letters with `Text(verbatim:)`. These two keys already ship in every language.
    var label: String {
        switch self {
        case .positionX: String(localized: "X position")
        case .positionY: String(localized: "Y position")
        case .width: String(localized: "Width")
        case .height: String(localized: "Height")
        case .text: String(localized: "Text")
        case .font: String(localized: "Font")
        case .fontSize: String(localized: "Size")
        case .fontWeight: String(localized: "Weight")
        case .textAlign: String(localized: "Alignment")
        case .italic: String(localized: "Italic")
        case .uppercase: String(localized: "Uppercase")
        case .letterSpacing: String(localized: "Letter Spacing")
        case .lineSpacing: String(localized: "Line Spacing")
        case .lineHeight: String(localized: "Line Height")
        case .image: String(localized: "Image")
        }
    }

    /// Overridden property names in declaration order. Sorting by `allCases` rather than by name
    /// keeps the list stable as the set changes.
    static func summary(_ fields: Set<LocaleOverrideField>) -> String {
        allCases.filter(fields.contains).map(\.label).formatted(.list(type: .and))
    }

    /// One construction site for a string two surfaces show, so rewording it can't fork the
    /// catalog key and orphan its translations.
    static func overriddenHelp(_ fields: Set<LocaleOverrideField>, language: String) -> Text {
        Text("Overridden for \(language): \(summary(fields))")
    }
}

/// Which properties the active locale overrides on the shape a surface is editing. Containers
/// resolve this once from the document and inject it; leaf controls read it through
/// `.localeOverridden(_:)`. Deriving it from the document rather than from a binding is what keeps
/// a 30 Hz slider drag from invalidating every marked control in the surface.
struct LocaleOverrideMarks: Equatable {
    let shapeId: UUID
    let fields: Set<LocaleOverrideField>
}

extension EnvironmentValues {
    /// nil in the base language, where no mark can ever render.
    @Entry var localeOverrideMarks: LocaleOverrideMarks?
}

extension View {
    /// Injected once per editing surface, so the leaf controls below cost one environment read
    /// rather than a document scan each.
    func localeOverrideMarks(shapeId: UUID, fields: Set<LocaleOverrideField>) -> some View {
        environment(\.localeOverrideMarks, fields.isEmpty ? nil : LocaleOverrideMarks(shapeId: shapeId, fields: fields))
    }
}

extension View {
    /// Washes the control in the locale accent when this language overrides it. A wash rather than
    /// a badge because every changed control carries one: a dot per field read as clutter, and
    /// anything that occupies layout reflows the properties bar the moment an override appears.
    func localeOverridden(_ field: LocaleOverrideField) -> some View {
        modifier(LocaleOverriddenModifier(field: field))
    }

    /// Tints a glyph the same accent, for a control whose meaning *is* the overridden field — the
    /// properties bar's globe opens the translation editor. Reads the same environment the wash
    /// does, so the two can't disagree about what this language overrides.
    func localeOverriddenTint(_ field: LocaleOverrideField) -> some View {
        modifier(LocaleOverriddenTintModifier(field: field))
    }
}

private struct LocaleOverriddenTintModifier: ViewModifier {
    @Environment(\.localeOverrideMarks) private var marks
    let field: LocaleOverrideField

    func body(content: Content) -> some View {
        content.foregroundStyle(marks?.fields.contains(field) == true ? Color.localeWarning : Color.primary)
    }
}

/// The tint is always applied and only its alpha changes, so the control keeps one structural
/// identity. Swapping between a marked and unmarked *branch* would rebuild it — and the edit that
/// first creates an override is made in the very field that would be torn down, losing its
/// in-progress text and focus.
private struct LocaleOverriddenModifier: ViewModifier {
    @Environment(\.localeOverrideMarks) private var marks
    let field: LocaleOverrideField

    func body(content: Content) -> some View {
        let isMarked = marks?.fields.contains(field) == true
        return content.overlay {
            RoundedRectangle(cornerRadius: UIMetrics.OverrideMark.cornerRadius, style: .continuous)
                .fill(Color.localeWarning.opacity(isMarked ? UIMetrics.OverrideMark.tint : 0))
                .allowsHitTesting(false)
        }
    }
}

/// A count of overridden things — properties in an inspector section header, shapes in a row
/// header. Carries no tooltip of its own because those two read differently; callers attach one.
struct LocaleOverrideCountBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color.localeWarning)
                .frame(width: UIMetrics.OverrideMark.dot, height: UIMetrics.OverrideMark.dot)
            Text(count, format: .number)
                .scaledFont(UIMetrics.FontSize.numericBadge, weight: .medium)
                .monospacedDigit()
        }
        .statusBadgeCapsule(Color.localeWarning)
    }
}

/// The selection's override summary: which language, how many overridden things, and the reset
/// menu. `count` is properties for one shape and shapes for a multi-selection, so the tooltip
/// comes from the caller rather than being guessed here.
///
/// The menu is where per-property reset lives. It can't live on the controls: a right-click menu
/// there would displace the text fields' own Cut/Copy/Paste, and anything applied only to the
/// overridden ones changes their view identity, which would tear down the field mid-edit at the
/// moment the first override is created.
struct LocaleOverrideChip: View {
    /// What the chip is summarising. `count` and the reset affordance both follow from this, so a
    /// caller can't pair a shape count with a property tooltip, or forget to pass either.
    enum Scope {
        /// One shape: the count is properties, and each can be reset on its own.
        case shape(id: UUID, fields: Set<LocaleOverrideField>)
        /// A selection: the count is shapes, and reset is all-or-nothing — there is no per-property
        /// reset across shapes.
        case selection(ids: Set<UUID>)
    }

    let scope: Scope
    let state: AppState

    private var localeLabel: String { state.localeState.activeLocaleLabel }

    private var count: Int {
        switch scope {
        case .shape(_, let fields): fields.count
        case .selection(let ids): ids.count
        }
    }

    private var help: Text {
        switch scope {
        case .shape(_, let fields):
            LocaleOverrideField.overriddenHelp(fields, language: localeLabel)
        case .selection(let ids):
            Text("\(ids.count) of the selected shapes are overridden for \(localeLabel)")
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            // The language name is the first thing to go in a narrow inspector — the globe and the
            // count still say "this language overrides N things", and the tooltip names it.
            ViewThatFits(in: .horizontal) {
                badge(showsLanguage: true)
                badge(showsLanguage: false)
            }

            switch scope {
            case .shape(let id, let fields):
                resetMenu(shapeId: id, fields: fields)
            case .selection(let ids):
                ActionButton(
                    icon: "arrow.counterclockwise",
                    tooltip: "Reset all overrides for this language",
                    frameSize: UIMetrics.IconButton.frameSize
                ) {
                    state.resetLocaleOverrides(shapeIds: ids)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func resetMenu(shapeId: UUID, fields: Set<LocaleOverrideField>) -> some View {
        Menu {
            Section("Reset for this language") {
                ForEach(LocaleOverrideField.allCases.filter(fields.contains), id: \.self) { field in
                    Button(field.label) {
                        state.clearLocaleOverrideField(shapeId: shapeId, field: field)
                    }
                }
            }
            Button("Reset All", role: .destructive) {
                state.resetLocaleOverride(shapeId: shapeId)
            }
        } label: {
            // Shares ActionButton's label so the menu keeps its iPad touch-target floor; a
            // hand-rolled 24pt frame put this control below it on iPad.
            IconButtonLabel(tooltip: "Reset language override", icon: "arrow.counterclockwise", frameSize: UIMetrics.IconButton.frameSize)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("Reset overrides for this language")
    }

    private func badge(showsLanguage: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "globe")
            if showsLanguage {
                Text(localeLabel)
                    .lineLimit(1)
            }
            Text(count, format: .number)
                .monospacedDigit()
                .opacity(UIMetrics.Opacity.accentEmphasis)
        }
        .scaledFont(UIMetrics.FontSize.inlineLabel, weight: .medium)
        .fixedSize()
        .statusBadgeCapsule(Color.localeWarning)
        .help(help)
    }
}
