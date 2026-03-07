import SwiftUI

struct FontPicker: View {
    @Binding var selection: String

    private static let fontFamilies: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted()
    }()

    var body: some View {
        Picker("", selection: $selection) {
            Text("System").tag("")
            Divider()
            ForEach(Self.fontFamilies, id: \.self) { family in
                Text(family)
                    .tag(family)
            }
        }
        .labelsHidden()
        .frame(width: 140)
    }
}
