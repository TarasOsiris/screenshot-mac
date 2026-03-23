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
        if selection.isEmpty { return "System" }
        return selection
    }

    private func pickCustomFont() {
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

                fontButton("System", value: "")

                if !sortedCustomFamilies.isEmpty {
                    Divider()
                    ForEach(sortedCustomFamilies, id: \.self) { family in
                        fontButton(family, value: family)
                    }
                }

                Divider()
                ForEach(Self.fontFamilies, id: \.self) { family in
                    fontButton(family, value: family)
                }
            } label: {
                HStack(spacing: 6) {
                    Text(displayName)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 130, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
    }
}
