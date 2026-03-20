import SwiftUI

/// Screenshot size picker used in both Settings and Onboarding.
struct ScreenshotSizePicker: View {
    @Binding var selection: String
    var label: String = "Default screenshot size"

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(displayCategories) { category in
                Section(category.name) {
                    ForEach(category.sizes, id: \.label) { size in
                        Text(size.displayLabel)
                            .tag("\(Int(size.width))x\(Int(size.height))")
                    }
                }
            }
        }
        .pickerStyle(.menu)
    }
}

/// Default device picker row used in both Settings and Onboarding.
struct DefaultDevicePicker: View {
    @Binding var categoryRaw: String
    @Binding var frameId: String

    var body: some View {
        LabeledContent("Default device") {
            DevicePickerMenu(
                category: DeviceCategory(rawValue: categoryRaw),
                frameId: frameId.isEmpty ? nil : frameId,
                onSelectNone: {
                    categoryRaw = ""
                    frameId = ""
                },
                onSelectCategory: { cat in
                    categoryRaw = cat.rawValue
                    frameId = ""
                },
                onSelectFrame: { frame in
                    categoryRaw = frame.fallbackCategory.rawValue
                    frameId = frame.id
                }
            )
        }
    }
}

/// Template count picker used in both Settings and Onboarding.
struct TemplateCountPicker: View {
    @Binding var selection: Int
    var label: String = "Screenshots per new row"

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(1...6, id: \.self) { count in
                Text(verbatim: "\(count)").tag(count)
            }
        }
    }
}
