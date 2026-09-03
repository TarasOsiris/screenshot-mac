import SwiftUI

#if os(macOS)
struct HelpParagraph: View {
    let text: LocalizedStringResource
    init(_ text: LocalizedStringResource) { self.text = text }
    var body: some View {
        HelpText(text)
            .font(.body)
            .foregroundStyle(.primary)
    }
}
#endif
