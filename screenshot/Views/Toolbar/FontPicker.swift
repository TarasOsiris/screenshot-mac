import SwiftUI
import UniformTypeIdentifiers

struct FontPicker: View {
    @Binding var selection: String
    var customFonts: [String: String] = [:]  // fileName → familyName
    var onImportFont: ((URL) -> Void)?

    private static let fontFamilies: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted()
    }()

    private var sortedCustomFamilies: [String] {
        Set(customFonts.values).sorted()
    }

    var body: some View {
        HStack(spacing: 4) {
            Picker("", selection: $selection) {
                Text("System").tag("")

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
                for url in panel.urls {
                    onImportFont?(url)
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
