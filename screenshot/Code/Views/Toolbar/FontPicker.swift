import SwiftUI
import UniformTypeIdentifiers

struct FontPicker: View {
    @Binding var selection: String
    var fontWeight: Binding<Int>? = nil
    var italic: Binding<Bool>? = nil
    var customFonts: [String: CustomFont] = [:]  // fileName → CustomFont
    var onImportFont: ((URL) -> ImportedCustomFontSelection?)?

    private static let fontFamilies: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted()
    }()

    private var customFontEntries: [String] {
        customFonts.values.map(\.displayName).sorted()
    }

    @ViewBuilder
    private func fontButton(_ label: String, value: String) -> some View {
        Button {
            if let custom = CustomFontRegistry.font(forDisplayName: value) {
                applyImportedSelection(custom.selectionResult())
            } else {
                selection = value
            }
        } label: {
            if selection == value {
                Label(label, systemImage: "checkmark")
            } else {
                Text(label)
            }
        }
    }

    private func applyImportedSelection(_ imported: ImportedCustomFontSelection) {
        selection = imported.fontName
        if let value = imported.fontWeight {
            fontWeight?.wrappedValue = value
        }
        if let value = imported.italic {
            italic?.wrappedValue = value
        }
    }

    private var displayName: String {
        if selection.isEmpty { return String(localized: "System") }
        return selection
    }

    private func pickCustomFont() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.font]
        panel.allowsMultipleSelection = true
        // Allow picking a folder so all variants (Bold, Italic, BoldItalic, ...) get
        // imported in one gesture. Sandbox grants access to the chosen folder's contents.
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.message = String(localized: "Pick a font file or a folder containing all variants")
        guard panel.runModal() == .OK else { return }
        var lastImportedSelection: ImportedCustomFontSelection?
        for url in panel.urls {
            if let imported = onImportFont?(url) {
                lastImportedSelection = imported
            }
        }
        if let lastImportedSelection {
            applyImportedSelection(lastImportedSelection)
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                Button {
                    pickCustomFont()
                } label: {
                    Label("Pick custom font", systemImage: "plus")
                }

                Divider()

                fontButton(String(localized: "System"), value: "")

                if !customFontEntries.isEmpty {
                    Divider()
                    ForEach(customFontEntries, id: \.self) { name in
                        fontButton(name, value: name)
                    }
                }

                Divider()
                ForEach(Self.fontFamilies, id: \.self) { family in
                    fontButton(family, value: family)
                }
            } label: {
                Text(displayName)
                    .lineLimit(1)
                    .frame(width: 130, alignment: .leading)
            }
            .menuStyle(.button)
            .fixedSize()
        }
    }
}
