import SwiftUI

/// Buffers edits locally so binding straight to @Observable AppState doesn't reset the
/// caret on every keystroke (the body recomputes and re-feeds the value otherwise).
struct BufferedTranslationField: View {
    let placeholder: String
    @Binding var text: String
    var lineLimit: ClosedRange<Int>
    @State private var localText: String
    @FocusState private var isFocused: Bool

    init(placeholder: String, text: Binding<String>, lineLimit: ClosedRange<Int> = 1...6) {
        self.placeholder = placeholder
        self._text = text
        self.lineLimit = lineLimit
        self._localText = State(initialValue: text.wrappedValue)
    }

    var body: some View {
        TextField(placeholder, text: $localText, axis: .vertical)
            .lineLimit(lineLimit)
            .focused($isFocused)
            .debouncedFieldCommit(buffer: $localText, into: $text, isFocused: isFocused)
    }
}

/// Commits a cell's local editing buffer into its `@Observable`-backed binding on a debounce, and
/// flushes immediately when the cell disappears (sheet dismiss, List/LazyVStack recycling). Writing
/// the model on every keystroke would mutate `localeState`/`rows` and rebuild the entire grid per
/// keystroke; debouncing means only the focused cell re-renders while typing.
struct DebouncedFieldCommit: ViewModifier {
    @Binding var buffer: String
    @Binding var committed: String
    var isFocused: Bool
    var delay: TimeInterval = 0.3
    @State private var commitTask: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .onChange(of: buffer) { _, newValue in
                commitTask?.cancel()
                let task = DispatchWorkItem { if newValue != committed { committed = newValue } }
                commitTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
            }
            .onChange(of: committed) { _, newValue in
                // An external write (Translate, auto-translate, locale switch) supersedes any in-flight
                // buffer commit — cancel it so a stale debounce can't revert the new value.
                guard newValue != buffer else { return }
                commitTask?.cancel()
                commitTask = nil
                buffer = newValue
            }
            .onChange(of: isFocused) { _, focused in
                // Commit immediately on blur so leaving the cell (e.g. to click Translate) flushes
                // the latest text, and nothing is left pending past the edit.
                if !focused { flush() }
            }
            .onDisappear { flush() }
    }

    private func flush() {
        commitTask?.cancel()
        commitTask = nil
        if buffer != committed { committed = buffer }
    }
}

extension View {
    func debouncedFieldCommit(buffer: Binding<String>, into committed: Binding<String>, isFocused: Bool) -> some View {
        modifier(DebouncedFieldCommit(buffer: buffer, committed: committed, isFocused: isFocused))
    }
}

/// Plain text of a *formatted* translation override, or nil when it carries no rich text.
/// Rich-text translations are shown read-only — a plain field can't edit formatting and the
/// `richText` override wins at render time anyway.
func formattedTranslationPlainText(for override: ShapeLocaleOverride?) -> String? {
    guard let override, let richText = override.richText, !richText.isEmpty else { return nil }
    // Prefer the stored plain-text mirror; only decode the RTF when there isn't one.
    return override.text ?? RichTextUtils.plainText(from: richText) ?? ""
}

/// Override text binding for one locale; a blank value resets to the base language. Reads/writes
/// through the shape's (possibly shared) translation key, so reused strings stay in sync.
func localeTranslationBinding(_ state: AppState, shape: CanvasShapeModel, localeCode: String) -> Binding<String> {
    Binding(
        get: { state.translationOverrideForDisplay(shape: shape, localeCode: localeCode)?.text ?? "" },
        set: { newValue in
            if isUntranslated(newValue) {
                state.resetTranslationText(shapeId: shape.id, localeCode: localeCode)
            } else {
                state.updateTranslationText(shapeId: shape.id, localeCode: localeCode, text: newValue)
            }
        }
    )
}

/// Shared "Reuse Translation" pull-down: link this text to another string (sharing base text + all
/// translations) or stop reusing. Used by both the canvas context menu and the localization popover.
/// `targets` is a closure so the full (possibly large) target list is built only when the menu opens.
@ViewBuilder
func reuseTranslationMenuContent(
    isLinked: Bool,
    hasTargets: Bool,
    targets: @escaping () -> [(key: String, label: String)],
    onLink: @escaping (String) -> Void,
    onUnlink: (() -> Void)? = nil
) -> some View {
    if isLinked || hasTargets {
        Menu {
            if isLinked, let onUnlink {
                Button("Stop Reusing Translation", systemImage: "link.badge.minus", action: onUnlink)
                if hasTargets { Divider() }
            }
            if hasTargets {
                Section("Reuse translation from") {
                    ForEach(targets(), id: \.key) { target in
                        Button(target.label) { onLink(target.key) }
                    }
                }
            }
        } label: {
            Label("Reuse Translation", systemImage: "link")
        }
    }
}

#if os(macOS)
/// Multiline editor that uses `TextEditor` so Return inserts a newline (a
/// vertical-axis `TextField` treats Return as a submit gesture on macOS).
struct MultilineCellEditor: View {
    let placeholder: String
    @Binding var text: String
    var help: String? = nil

    // Local buffer: binding TextEditor straight to AppState-backed state recomputes
    // the body on every keystroke and re-feeds the value, resetting the caret to the
    // end. The buffer survives recomputes; we sync to/from `text` only on real changes.
    @State private var localText: String
    @State private var contentHeight: CGFloat = 0
    @FocusState private var isFocused: Bool

    private let fontSize: CGFloat = 12
    // Match the TextEditor's intrinsic text origin so the placeholder/mirror align.
    private let insetH: CGFloat = 5
    private let insetV: CGFloat = 5
    private let minHeight: CGFloat = 40   // ~2 lines
    private let maxHeight: CGFloat = 100  // ~6 lines

    init(placeholder: String, text: Binding<String>, help: String? = nil) {
        self.placeholder = placeholder
        self._text = text
        self.help = help
        self._localText = State(initialValue: text.wrappedValue)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Invisible mirror sizes the editor so it grows with the text instead
            // of clipping at a fixed height; shares the editor's width and insets.
            Text(localText.isEmpty ? placeholder : localText)
                .font(.system(size: fontSize))
                .padding(.horizontal, insetH)
                .padding(.vertical, insetV)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: CellHeightKey.self, value: proxy.size.height)
                })
                .hidden()

            if localText.isEmpty {
                Text(placeholder)
                    .font(.system(size: fontSize))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, insetH)
                    .padding(.vertical, insetV)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $localText)
                .font(.system(size: fontSize))
                .scrollContentBackground(.hidden)
                .focused($isFocused)
        }
        .frame(height: min(max(contentHeight, minHeight), maxHeight))
        .onPreferenceChange(CellHeightKey.self) { contentHeight = $0 }
        .debouncedFieldCommit(buffer: $localText, into: $text, isFocused: isFocused)
        .background(Color.platformTextBackground)
        .overlay(
            RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.card)
                .stroke(Color.platformSeparator, lineWidth: UIMetrics.BorderWidth.standard)
        )
        .clipShape(RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.card))
        .modifier(OptionalHelp(help: help))
    }
}

/// Intrinsic content height of a cell editor, used to size it to fit.
private struct CellHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct OptionalHelp: ViewModifier {
    let help: String?

    func body(content: Content) -> some View {
        if let help {
            content.help(help)
        } else {
            content
        }
    }
}
#endif
