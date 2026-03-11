import SwiftUI

/// Reusable menu content for device selection:
/// - Abstract devices (shape-based)
/// - Real frames grouped by model -> color -> orientation
struct DeviceMenuContent: View {
    let onSelectCategory: (DeviceCategory) -> Void
    let onSelectFrame: (DeviceFrame) -> Void

    var body: some View {
        Section("Abstract Devices") {
            ForEach(DeviceCategory.allCases, id: \.self) { cat in
                Button {
                    onSelectCategory(cat)
                } label: {
                    Label(cat.label, systemImage: cat.icon)
                }
            }
        }

        Divider()

        Section("Real Device Frames") {
            ForEach(DeviceFrameCatalog.groups) { group in
                Menu(group.name) {
                    ForEach(group.colorGroups) { colorGroup in
                        Menu(colorGroup.name) {
                            ForEach(colorGroup.frames) { frame in
                                Button {
                                    onSelectFrame(frame)
                                } label: {
                                    Label(
                                        frame.orientationLabel,
                                        systemImage: frame.isLandscape ? "rectangle" : "rectangle.portrait"
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
