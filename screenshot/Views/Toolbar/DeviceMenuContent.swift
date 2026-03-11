import SwiftUI

/// Reusable menu content for device selection: abstract devices, divider, real frames grouped by model.
struct DeviceMenuContent: View {
    let onSelectCategory: (DeviceCategory) -> Void
    let onSelectFrame: (DeviceFrame) -> Void

    var body: some View {
        ForEach(DeviceCategory.allCases, id: \.self) { cat in
            Button {
                onSelectCategory(cat)
            } label: {
                Label(cat.label, systemImage: cat.icon)
            }
        }

        Divider()

        ForEach(DeviceFrameCatalog.groups) { group in
            Menu(group.name) {
                ForEach(group.frames) { frame in
                    Button(frame.shortLabel) {
                        onSelectFrame(frame)
                    }
                }
            }
        }
    }
}
