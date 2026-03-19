import SwiftUI
import UniformTypeIdentifiers

struct FontPicker: View {
    @Binding var selection: String
    var customFonts: [String: String] = [:]  // fileName → familyName
    var onImportFont: ((URL) -> String?)?

    private static let fontFamilies: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted()
    }()

    private var sortedCustomFamilies: [String] {
        Set(customFonts.values).sorted()
    }

    /// True when the current selection is a non-system font that isn't in the
    /// custom fonts list (e.g. custom fonts dict was cleared momentarily).
    private var selectionMissingFromOptions: Bool {
        !selection.isEmpty
            && !sortedCustomFamilies.contains(selection)
            && !Self.fontFamilies.contains(selection)
    }

    var body: some View {
        HStack(spacing: 4) {
            Picker("", selection: $selection) {
                Text("System").tag("")

                // Keep the current selection as a tag so SwiftUI never
                // resets the binding when the font list changes.
                if selectionMissingFromOptions {
                    Text(selection).tag(selection)
                }

                if !sortedCustomFamilies.isEmpty {
                    Divider()
                    ForEach(sortedCustomFamilies, id: \.self) { family in
                        Text(family)
                            .tag(family)
                    }
                }

                Divider()
                ForEach(Self.fontFamilies, id: \.self) { family in
                    Text(family)
                        .tag(family)
                }
            }
            .labelsHidden()
            .frame(width: 130)

            Button {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.font]
                panel.allowsMultipleSelection = true
                panel.canChooseDirectories = false
                guard panel.runModal() == .OK else { return }
                var lastFamily: String?
                for url in panel.urls {
                    if let family = onImportFont?(url) {
                        lastFamily = family
                    }
                }
                if let family = lastFamily {
                    selection = family
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9))
            }
            .buttonStyle(.borderless)
            .help("Add custom font")
        }
    }
}
