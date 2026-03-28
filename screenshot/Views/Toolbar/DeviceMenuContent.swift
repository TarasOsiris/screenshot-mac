import SwiftUI

/// Reusable menu content for device selection:
/// - Groups devices by family (iPhone, iPad, MacBook)
/// - Each family shows generic device types plus concrete device models
struct DeviceMenuContent: View {
    let onSelectCategory: (DeviceCategory) -> Void
    let onSelectFrame: (DeviceFrame) -> Void
    var selectedCategory: DeviceCategory? = nil
    var selectedFrameId: String? = nil
    var usePreferredFrameButtons: Bool = false

    /// Device families group related categories and real frame groups together.
    private struct DeviceFamily: Identifiable {
        var id: String { name }
        let name: String
        let categories: [DeviceCategory]
        let groups: [DeviceFrameGroup]
    }

    private static let ipadCategories: Set<DeviceCategory> = [.ipadPro11, .ipadPro13]
    private static let androidCategories: Set<DeviceCategory> = [.androidPhone, .androidTablet]

    private static let families: [DeviceFamily] = {
        let allGroups = DeviceFrameCatalog.groups
        return [
            DeviceFamily(
                name: "iPhone",
                categories: [.iphone],
                groups: allGroups.filter { $0.frames.first?.fallbackCategory == .iphone }
            ),
            DeviceFamily(
                name: "Android",
                categories: [.androidPhone, .androidTablet],
                groups: allGroups.filter { androidCategories.contains($0.frames.first?.fallbackCategory ?? .iphone) }
            ),
            DeviceFamily(
                name: "iPad",
                categories: [.ipadPro11, .ipadPro13],
                groups: allGroups.filter { ipadCategories.contains($0.frames.first?.fallbackCategory ?? .iphone) }
            ),
            DeviceFamily(
                name: "Mac",
                categories: [.macbook],
                groups: allGroups.filter { $0.frames.first?.fallbackCategory == .macbook }
            ),
        ]
    }()

    private var selectedGroupId: String? {
        guard let selectedFrameId else { return nil }
        return DeviceFrameCatalog.group(forFrameId: selectedFrameId)?.id
    }

    private func menuRowLabel(_ title: String, icon: String, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer(minLength: 12)
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func categoryButton(_ category: DeviceCategory) -> some View {
        Button {
            onSelectCategory(category)
        } label: {
            menuRowLabel(
                "Generic \(category.label)",
                icon: category.icon,
                isSelected: selectedFrameId == nil && selectedCategory == category
            )
        }
    }

    private func frameButton(_ frame: DeviceFrame, label: String, isSelected: Bool = false) -> some View {
        Button {
            onSelectFrame(frame)
        } label: {
            menuRowLabel(
                label,
                icon: frame.icon,
                isSelected: isSelected
            )
        }
    }

    @ViewBuilder
    private func groupContent(_ group: DeviceFrameGroup) -> some View {
        if usePreferredFrameButtons {
            if let frame = DeviceFrameCatalog.preferredFrame(forGroupId: group.id, matching: selectedFrameId) {
                frameButton(
                    frame,
                    label: group.name,
                    isSelected: selectedGroupId == group.id
                )
            }
        } else if group.frames.count == 1, let frame = group.frames.first {
            frameButton(frame, label: group.name, isSelected: selectedFrameId == frame.id)
        } else {
            Menu(group.name) {
                ForEach(Array(group.colorGroups.enumerated()), id: \.element.id) { index, colorGroup in
                    if colorGroup.frames.count == 1, let frame = colorGroup.frames.first {
                        frameButton(
                            frame,
                            label: colorGroup.name,
                            isSelected: selectedFrameId == frame.id
                        )
                    } else {
                        ForEach(colorGroup.frames) { frame in
                            frameButton(
                                frame,
                                label: "\(colorGroup.name) - \(frame.orientationLabel)",
                                isSelected: selectedFrameId == frame.id
                            )
                        }
                    }
                    if index < group.colorGroups.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    var body: some View {
        ForEach(Self.families) { family in
            Section(family.name) {
                ForEach(family.categories, id: \.self) { cat in
                    categoryButton(cat)
                }

                if !family.categories.isEmpty && !family.groups.isEmpty {
                    Divider()
                }

                ForEach(family.groups) { group in
                    groupContent(group)
                }
            }
        }
    }
}
