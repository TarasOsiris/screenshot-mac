import SwiftUI

/// A `ColorPicker` with the project's saved colors and its document colors one click away.
/// Drop-in for `ColorPicker(_:selection:supportsOpacity:)`; label modifiers apply to the well.
struct PaletteColorPicker: View {
    let titleKey: LocalizedStringKey
    @Binding var selection: Color
    var supportsOpacity = true
    /// Sizes the color well alone, so a compact toolbar frame doesn't squeeze out the palette button.
    var wellWidth: CGFloat?

    @Environment(AppState.self) private var state: AppState?
    @State private var isPalettePresented = false

    init(_ titleKey: LocalizedStringKey, selection: Binding<Color>, supportsOpacity: Bool = true, wellWidth: CGFloat? = nil) {
        self.titleKey = titleKey
        self._selection = selection
        self.supportsOpacity = supportsOpacity
        self.wellWidth = wellWidth
    }

    var body: some View {
        HStack(spacing: 2) {
            ColorPicker(titleKey, selection: $selection, supportsOpacity: supportsOpacity)
                .frame(width: wellWidth)
            if let state {
                Button {
                    isPalettePresented.toggle()
                } label: {
                    Image(systemName: "swatchpalette")
                        .scaledFont(UIMetrics.FontSize.inlineLabel)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Project Colors")
                .barPopover(isPresented: $isPalettePresented, title: "Project Colors") {
                    PaletteSwatchesView(state: state, selection: $selection)
                }
            }
        }
    }
}

private struct PaletteSwatchesView: View {
    let state: AppState
    @Binding var selection: Color
    /// Taken when the popover opens: the walk covers every shape, and edits made from inside the
    /// popover shouldn't re-run it.
    @State private var documentColors: [CodableColor] = []

    private let columns = Array(repeating: GridItem(.fixed(UIMetrics.ColorSwatch.preview), spacing: 6), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Project Colors")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    state.addPaletteColor(selection)
                } label: {
                    Label("Add Current Color", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Save the current color to this project")
            }
            if state.palette.isEmpty {
                Text("Save colors here to reuse them anywhere in this project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                swatchGrid(state.palette, removable: true)
            }

            if !documentColors.isEmpty {
                Divider()
                Text("Document Colors")
                    .font(.subheadline.weight(.semibold))
                swatchGrid(documentColors, removable: false)
            }
        }
        .padding(12)
        .frame(width: 6 * UIMetrics.ColorSwatch.preview + 5 * 6 + 24)
        .onAppear { documentColors = state.documentColors() }
    }

    private func swatchGrid(_ colors: [CodableColor], removable: Bool) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                Button {
                    selection = color.color
                } label: {
                    RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip)
                        .fill(color.color)
                        .frame(width: UIMetrics.ColorSwatch.preview, height: UIMetrics.ColorSwatch.preview)
                        .overlay {
                            RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip)
                                .strokeBorder(.separator, lineWidth: UIMetrics.BorderWidth.hairline)
                        }
                }
                .buttonStyle(.plain)
                .help(color.color.hexString.uppercased())
                .contextMenu {
                    if removable {
                        Button("Remove from Project Colors", systemImage: "trash", role: .destructive) {
                            state.removePaletteColor(color)
                        }
                    } else {
                        Button("Save to Project Colors", systemImage: "plus") {
                            state.addPaletteColor(color.color)
                            documentColors.removeAll { AppState.sameColor($0, color) }
                        }
                    }
                }
            }
        }
    }
}
