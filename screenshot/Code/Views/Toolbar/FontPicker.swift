import SwiftUI

struct FontPicker: View {
    enum Presentation {
        /// The bar's button: a fixed-width label drawn in the chosen font, so it stays steady.
        case menu
        /// The inspector's pop-up, matching its other pop-up rows (Preset, Style).
        case popUp
    }

    @Binding var selection: String
    var fontWeight: Binding<Int>?
    var italic: Binding<Bool>?
    var customFaces: [CustomFont] = []
    var onApplyImportedSelection: ((ImportedCustomFontSelection) -> Void)?
    var onImportFont: ((URL) -> ImportedCustomFontSelection?)?
    var presentation: Presentation = .menu

    private static let previewFontSize: CGFloat = 13
    private static let previewFontCache = NSCache<NSString, NSFont>()

    /// Resolves a SwiftUI `Font` for a family/display name and memoizes it so the menu only
    /// pays the Core Text lookup cost the first time each entry is rendered.
    fileprivate static func previewFont(for name: String) -> Font {
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

    fileprivate static let fontFamilies: [String] = {
        PlatformFonts.systemFamilyNames.sorted()
    }()
    fileprivate static let fontFamilySet = Set(fontFamilies)

    /// The picker's entries in order — System, imported faces, then every family — as
    /// (label, value) rows, so the bar's menu and the inspector's pop-up list the same thing.
    @ViewBuilder
    fileprivate static func fontItems<Row: View>(
        faceNames: [String],
        @ViewBuilder row: @escaping (_ label: String, _ value: String) -> Row
    ) -> some View {
        row(String(localized: "System"), "")
        if !faceNames.isEmpty {
            Divider()
            ForEach(faceNames, id: \.self) { name in row(name, name) }
        }
        Divider()
        ForEach(fontFamilies, id: \.self) { family in row(family, family) }
    }

    /// An imported face carries its own weight and italic; anything else is just a family name.
    private func choose(_ value: String) {
        if let custom = CustomFontRegistry.font(forDisplayName: value) {
            applyImportedSelection(custom.selectionResult())
        } else {
            selection = value
        }
    }

    @ViewBuilder
    private func fontButton(_ label: String, value: String) -> some View {
        Button {
            choose(value)
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
        switch presentation {
        case .menu: menu
        case .popUp: popUp
        }
    }

    private var menu: some View {
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

                Self.fontItems(faceNames: customFaces.map(\.displayName)) { label, value in
                    fontButton(label, value: value)
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

    private var popUp: some View {
        FontPopUp(
            selection: selection,
            displayName: displayName,
            faceNames: customFaces.map(\.displayName),
            choose: choose,
            pickCustomFont: {
                #if os(macOS)
                pickCustomFont()
                #endif
            }
        )
        .equatable()
    }
}

/// The inspector's font pop-up. Equatable on what it shows, so the several hundred rows are
/// rebuilt when the font or the imported faces change, not on every document edit.
private struct FontPopUp: View, Equatable {
    let selection: String
    let displayName: String
    let faceNames: [String]
    let choose: (String) -> Void
    let pickCustomFont: () -> Void

    /// Stands in for the "Pick custom font" action, which a `Picker` can only offer as an item.
    private static let importTag = "\u{0}import"

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.selection == rhs.selection && lhs.faceNames == rhs.faceNames
    }

    var body: some View {
        let isListed = selection.isEmpty || FontPicker.fontFamilySet.contains(selection) || faceNames.contains(selection)
        Picker(selection: binding) {
            #if os(macOS)
            Label("Pick custom font", systemImage: "plus").tag(Self.importTag)
            Divider()
            #endif
            if !isListed {
                row(displayName, value: selection)
            }
            FontPicker.fontItems(faceNames: faceNames) { label, value in
                row(label, value: value)
            }
        } label: {
            Text("Font")
        } currentValueLabel: {
            // The row's own font: the chosen face's preview belongs in the menu, not the value.
            Text(verbatim: displayName)
        }
        .inspectorPopUpPicker()
    }

    private func row(_ label: String, value: String) -> some View {
        Text(verbatim: label).font(FontPicker.previewFont(for: value)).tag(value)
    }

    private var binding: Binding<String> {
        Binding(
            get: { selection },
            set: { value in
                if value == Self.importTag {
                    // After the menu closes, so the open panel isn't raised from inside its tracking.
                    DispatchQueue.main.async { pickCustomFont() }
                } else {
                    choose(value)
                }
            }
        )
    }
}
