import SwiftUI

#if os(macOS)
struct HelpSeeAlso: View {
    let sections: [HelpSection]
    @Environment(\.openHelpSection) private var openSection

    var body: some View {
        HStack(spacing: 8) {
            Text("See also")
                .foregroundStyle(.secondary)
            ForEach(sections) { section in
                Button { openSection(section) } label: { section.label }
                    .buttonStyle(.link)
            }
        }
        .font(.body)
        .padding(.top, 4)
    }
}
#endif
