import SwiftUI
import UniformTypeIdentifiers

struct FontPicker: View {
    @Binding var selection: String
    var customFonts: [String: CustomFont] = [:]  // fileName → CustomFont
    var onImportFont: ((URL) -> String?)?

    private static let fontFamilies: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted()
    }()

    /// Picker entries for imported custom fonts. When a family has a regular variant
    /// (e.g. all four Tinos files imported), we collapse to a single family entry — the
    /// existing weight/italic toggles drive Bold/Italic via NSFontManager. When only
    /// non-regular variants exist (e.g. just Playfair Italic), we list them by display
    /// name so the user can still pick the variant they imported.
    private var customFontEntries: [String] {
        let byFamily = Dictionary(grouping: customFonts.values, by: { $0.familyName })
        var entries: Set<String> = []
        for (family, variants) in byFamily {
            if variants.contains(where: { $0.displayName == family }) {
                entries.insert(family)
            } else {
                for v in variants { entries.insert(v.displayName) }
            }
        }
        return entries.sorted()
    }

    @ViewBuilder
    private func fontButton(_ label: String, value: String) -> some View {
        Button {
            selection = value
        } label: {
            if selection == value {
                Label(label, systemImage: "checkmark")
            } else {
                Text(label)
            }
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
        var lastDisplayName: String?
        for url in panel.urls {
            if let name = onImportFont?(url) {
                lastDisplayName = name
            }
        }
        if let name = lastDisplayName {
            selection = name
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
