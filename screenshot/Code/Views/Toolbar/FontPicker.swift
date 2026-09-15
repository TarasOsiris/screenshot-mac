import SwiftUI

struct FontPicker: View {
    @Binding var selection: String
    var fontWeight: Binding<Int>?
    var italic: Binding<Bool>?
    var customFaces: [CustomFont] = []
    var onApplyImportedSelection: ((ImportedCustomFontSelection) -> Void)?
    var onImportFont: ((URL) -> ImportedCustomFontSelection?)?

    private static let previewFontSize: CGFloat = 13
    private static let previewFontCache = NSCache<NSString, NSFont>()

    /// Resolves a SwiftUI `Font` for a family/display name and memoizes it so the menu only
    /// pays the Core Text lookup cost the first time each entry is rendered.
    private static func previewFont(for name: String) -> Font {
        if name.isEmpty { return .system(size: previewFontSize) }
        let key = name as NSString
        if let cached = previewFontCache.object(forKey: key) {
            return Font(cached)
        }
        let ns = CustomFontRegistry.resolveNSFont(
            name: name, size: previewFontSize, managerWeight: 5, italic: false
        )
        previewFontCache.setObject(ns, forKey: key)
        return Font(ns)
    }

    private static let fontFamilies: [String] = {
        PlatformFonts.systemFamilyNames.sorted()
    }()

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
                Label {
                    Text(label).font(Self.previewFont(for: value))
                } icon: {
                    Image(systemName: "checkmark")
                }
            } else {
                Text(label).font(Self.previewFont(for: value))
            }
        }
    }

    private func applyImportedSelection(_ imported: ImportedCustomFontSelection) {
        if let onApplyImportedSelection {
            onApplyImportedSelection(imported)
            return
        }
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

    #if os(macOS)
    private func pickCustomFont() {
        var lastImportedSelection: ImportedCustomFontSelection?
        for url in FilePicker.pickFontFilesOrFolder() {
            if let imported = onImportFont?(url) {
                lastImportedSelection = imported
            }
        }
        if let lastImportedSelection {
            applyImportedSelection(lastImportedSelection)
        }
    }
    #endif
    // iOS: custom-font import via fileImporter is deferred to a follow-up.

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                #if os(macOS)
                // iOS custom-font import is deferred; hide the item rather than show a no-op.
                Button {
                    pickCustomFont()
                } label: {
                    Label("Pick custom font", systemImage: "plus")
                }

                Divider()
                #endif

                fontButton(String(localized: "System"), value: "")

                if !customFaces.isEmpty {
                    Divider()
                    ForEach(customFaces, id: \.displayName) { face in
                        fontButton(face.displayName, value: face.displayName)
                    }
                }

                Divider()
                ForEach(Self.fontFamilies, id: \.self) { family in
                    fontButton(family, value: family)
                }
            } label: {
                Text(displayName)
                    .font(Self.previewFont(for: selection))
                    .lineLimit(1)
                    .frame(width: 130, alignment: .leading)
            }
            .menuStyle(.button)
            .fixedSize()
        }
    }
}
