import SwiftUI

/// Reusable menu content for device selection:
/// - Groups devices by family (iPhone, iPad, MacBook)
/// - Each family shows abstract device + real frame variants
struct DeviceMenuContent: View {
    let onSelectCategory: (DeviceCategory) -> Void
    let onSelectFrame: (DeviceFrame) -> Void

    /// Device families group related categories and real frame groups together.
    private struct DeviceFamily: Identifiable {
        var id: String { name }
        let name: String
        let categories: [DeviceCategory]
        let groups: [DeviceFrameGroup]
    }

    private static let ipadCategories: Set<DeviceCategory> = [.ipadPro11, .ipadPro13]

    private var families: [DeviceFamily] {
        let allGroups = DeviceFrameCatalog.groups
        return [
            DeviceFamily(
                name: "iPhone",
                categories: [.iphone],
                groups: allGroups.filter { $0.frames.first?.fallbackCategory == .iphone }
            ),
            DeviceFamily(
                name: "iPad",
                categories: [.ipadPro11, .ipadPro13],
                groups: allGroups.filter { Self.ipadCategories.contains($0.frames.first?.fallbackCategory ?? .iphone) }
            ),
            DeviceFamily(
                name: "Mac",
                categories: [],
                groups: allGroups.filter { $0.frames.first?.fallbackCategory == .macbook }
            ),
        ]
    }

    private func menuRowLabel(_ title: String, icon: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
        }
    }

    private func categoryButton(_ category: DeviceCategory) -> some View {
        Button {
            onSelectCategory(category)
        } label: {
            menuRowLabel(
                "Abstract \(category.label)",
                icon: category.icon
            )
        }
    }

    private func frameButton(_ frame: DeviceFrame, label: String) -> some View {
        Button {
            onSelectFrame(frame)
        } label: {
            menuRowLabel(
                label,
                icon: frame.isLandscape ? "rectangle" : "rectangle.portrait"
            )
        }
    }

    var body: some View {
        ForEach(families) { family in
            Section(family.name) {
                ForEach(family.categories, id: \.self) { cat in
                    categoryButton(cat)
                }

                if !family.categories.isEmpty && !family.groups.isEmpty {
                    Divider()
                }

                ForEach(family.groups) { group in
                    if group.frames.count == 1, let frame = group.frames.first {
                        frameButton(frame, label: group.name)
                    } else {
                        Menu(group.name) {
                            ForEach(Array(group.colorGroups.enumerated()), id: \.element.id) { index, colorGroup in
                                if colorGroup.frames.count == 1, let frame = colorGroup.frames.first {
                                    frameButton(frame, label: colorGroup.name)
                                } else {
                                    ForEach(colorGroup.frames) { frame in
                                        frameButton(frame, label: "\(colorGroup.name) - \(frame.orientationLabel)")
                                    }
                                }
                                if index < group.colorGroups.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
