import SwiftUI

struct FontWeightPicker: View {
    @Binding var selection: Int
    var options: [Int] = [300, 400, 500, 700]
    var width: CGFloat = 100

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.self) { weight in
                Text(RichTextUtils.fontWeightLabel(weight)).tag(weight)
            }
        }
        .labelsHidden()
        .frame(width: width)
    }
}
