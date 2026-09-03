import SwiftUI

#if os(macOS)
struct HelpBullet: View {
    let text: LocalizedStringResource
    init(_ text: LocalizedStringResource) { self.text = text }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            HelpText(text)
        }
    }
}
#endif
