import SwiftUI

#if os(macOS)
struct AttributionsSettingsPane: View {
    var body: some View {
        Form {
            ForEach(AppAttribution.Category.allCases) { category in
                Section(category.title) {
                    ForEach(AppAttribution.inCategory(category)) { credit in
                        AttributionRow(credit: credit)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
#endif
