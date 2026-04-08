import SwiftUI

enum DevicePickerPresentation {
    case form
    case inline
    case sidebar
    case toolbar
}

/// Reusable device picker control used across settings, onboarding/new-project,
/// inspector, and toolbar surfaces.
struct DevicePickerMenu: View {
    let category: DeviceCategory?
    let frameId: String?
    var allowsNoDevice: Bool = true
    var presentation: DevicePickerPresentation = .form
    var bodyColor: Binding<Color>? = nil
    var bodyColorLabel: String = "Color"
    var canResetBodyColor: Bool = false
    var onResetBodyColor: (() -> Void)? = nil
    var onSelectNone: () -> Void = {}
    let onSelectCategory: (DeviceCategory) -> Void
    let onSelectFrame: (DeviceFrame) -> Void

    private var resolvedFrame: DeviceFrame? {
        frameId.flatMap { DeviceFrameCatalog.frame(for: $0) }
    }

    private var resolvedGroup: DeviceFrameGroup? {
        frameId.flatMap { DeviceFrameCatalog.group(forFrameId: $0) }
    }

    private var resolvedLabel: String {
        if let frame = resolvedFrame {
            return frame.modelName
        }
        guard let category else { return "No device" }
        return category.label
    }

    private var resolvedIcon: String {
        if let frame = resolvedFrame {
            return frame.icon
        }
        guard let category else { return "rectangle.dashed" }
        return category.icon
    }

    private var showsColorOptions: Bool {
        (resolvedGroup?.colorGroups.count ?? 0) > 1
    }

    private var canToggleOrientation: Bool {
        guard let frameId else { return false }
        return DeviceFrameCatalog.toggledOrientation(for: frameId) != nil
    }

    private var layout: AnyLayout {
        switch presentation {
        case .sidebar:
            AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
        case .form, .inline, .toolbar:
            AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        }
    }

    var body: some View {
        layout {
            menuButton
            accessoryControls
        }
        .frame(maxWidth: presentation == .sidebar ? .infinity : nil, alignment: .leading)
    }

    @ViewBuilder
    private var menuButton: some View {
        let menu = Menu {
            if allowsNoDevice {
                Button {
                    onSelectNone()
                } label: {
                    Label("No device", systemImage: "rectangle.dashed")
                }

                Divider()
            }

            DeviceMenuContent(
                onSelectCategory: onSelectCategory,
                onSelectFrame: onSelectFrame,
                selectedCategory: category,
                selectedFrameId: frameId,
                usePreferredFrameButtons: true
            )
        } label: {
            menuLabel
        }

        switch presentation {
        case .toolbar:
            menu
                .menuStyle(.button)
                .fixedSize()
        case .sidebar:
            menu
                .menuStyle(.button)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .form, .inline:
            menu.menuStyle(.button)
        }
    }

    @ViewBuilder
    private var accessoryControls: some View {
        if let frame = resolvedFrame {
            frameAccessoryControls(frame: frame)
        } else if let bodyColor {
            bodyColorControls(bodyColor)
        }
    }

    @ViewBuilder
    private func frameAccessoryControls(frame: DeviceFrame) -> some View {
        let layout: AnyLayout = presentation == .sidebar
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 6))

        layout {
            if showsColorOptions, let group = resolvedGroup {
                labeledIfSidebar(group.prefersVariantMenu ? "Watch style" : "Frame color") {
                    if group.prefersVariantMenu {
                        DeviceFrameVariantSelector(
                            group: group,
                            selectedFrame: frame,
                            onSelectFrame: onSelectFrame
                        )
                    } else {
                        DeviceFrameColorSelector(
                            group: group,
                            selectedFrame: frame,
                            compact: true,
                            onSelectFrame: onSelectFrame
                        )
                    }
                }
            }

            if frame.isModelBacked, let bodyColor {
                bodyColorControls(bodyColor)
            }

            if canToggleOrientation {
                labeledIfSidebar("Orientation") {
                    OrientationPicker(isLandscape: orientationBinding(for: frame), labelsHidden: true)
                        .frame(width: 72, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func labeledIfSidebar<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if presentation == .sidebar {
            sidebarField(title, content: content)
        } else {
            content()
        }
    }

    @ViewBuilder
    private func bodyColorControls(_ bodyColor: Binding<Color>) -> some View {
        switch presentation {
        case .form:
            LabeledContent(bodyColorLabel) {
                HStack(spacing: 6) {
                    ColorPicker("", selection: bodyColor, supportsOpacity: false)
                        .labelsHidden()
                    resetBodyColorButton
                }
            }
        case .inline, .toolbar:
            HStack(spacing: 4) {
                ColorPicker("", selection: bodyColor, supportsOpacity: false)
                    .labelsHidden()
                    .help(bodyColorLabel)
                resetBodyColorButton
            }
        case .sidebar:
            sidebarField(bodyColorLabel) {
                HStack(spacing: 6) {
                    ColorPicker("", selection: bodyColor, supportsOpacity: false)
                        .labelsHidden()
                        .help(bodyColorLabel)
                    resetBodyColorButton
                }
            }
        }
    }

    private var menuLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: resolvedIcon)
            Text(resolvedLabel)
                .lineLimit(1)
                .truncationMode(.tail)

            if presentation == .sidebar {
                Spacer(minLength: 0)
            }
        }
    }

    private func sidebarField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var resetBodyColorButton: some View {
        if canResetBodyColor, let onResetBodyColor {
            ActionButton(
                icon: "arrow.counterclockwise",
                tooltip: "Reset \(bodyColorLabel.lowercased())",
                frameSize: 24
            ) {
                onResetBodyColor()
            }
        }
    }

    private func orientationBinding(for frame: DeviceFrame) -> Binding<Bool> {
        Binding(
            get: { frame.isLandscape },
            set: { newLandscape in
                guard newLandscape != frame.isLandscape,
                      let nextFrame = DeviceFrameCatalog.variant(
                          forFrameId: frame.id,
                          isLandscape: newLandscape
                      ) else { return }
                onSelectFrame(nextFrame)
            }
        )
    }
}

struct OrientationPicker: View {
    @Binding var isLandscape: Bool
    var labelsHidden: Bool = false

    var body: some View {
        let picker = Picker("Orientation", selection: $isLandscape) {
            Image(systemName: "rectangle.portrait")
                .tag(false)
            Image(systemName: "rectangle")
                .tag(true)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)

        if labelsHidden {
            picker.labelsHidden()
        } else {
            picker
        }
    }
}

private struct WatchVariantDescriptor {
    let bandName: String
    let title: String
    let subtitle: String?
    let selectionLabel: String

    init(variantName: String) {
        let finishes = ["Black", "Natural"]
        let bandNames = ["Alpine Loop", "Milanese Loop", "Ocean Band", "Trail Loop"]

        guard
            let finish = finishes.first(where: { variantName.hasPrefix("\($0) ") })
        else {
            bandName = "Watch"
            title = variantName
            subtitle = nil
            selectionLabel = variantName
            return
        }

        let remainder = String(variantName.dropFirst(finish.count + 1))
        let band = bandNames.first(where: { remainder.hasPrefix($0) }) ?? "Watch"
        let bandDetail = String(remainder.dropFirst(band.count)).trimmingCharacters(in: .whitespaces)

        bandName = band
        title = "\(finish) Case"
        subtitle = bandDetail.isEmpty ? nil : bandDetail
        selectionLabel = bandDetail.isEmpty
            ? "\(band) · \(finish)"
            : "\(band) · \(finish) / \(bandDetail)"
    }
}

private struct DeviceFrameVariantSelector: View {
    let group: DeviceFrameGroup
    let selectedFrame: DeviceFrame
    let onSelectFrame: (DeviceFrame) -> Void

    private struct VariantEntry: Identifiable {
        let id: String
        let colorGroup: DeviceFrameColorGroup
        let descriptor: WatchVariantDescriptor
    }

    private struct PickerSection: Identifiable {
        let id: String
        let title: String
        var entries: [VariantEntry]
    }

    private var selectedColorGroup: DeviceFrameColorGroup? {
        DeviceFrameCatalog.colorGroup(forFrameId: selectedFrame.id)
    }

    private var sections: [PickerSection] {
        var sections: [PickerSection] = []
        for colorGroup in group.colorGroups {
            let entry = VariantEntry(
                id: colorGroup.id,
                colorGroup: colorGroup,
                descriptor: WatchVariantDescriptor(variantName: colorGroup.name)
            )
            if let index = sections.firstIndex(where: { $0.title == entry.descriptor.bandName }) {
                sections[index].entries.append(entry)
            } else {
                sections.append(
                    PickerSection(
                        id: entry.descriptor.bandName,
                        title: entry.descriptor.bandName,
                        entries: [entry]
                    )
                )
            }
        }
        return sections
    }

    var body: some View {
        let selectedId = selectedColorGroup?.id
        let selectionLabel = selectedColorGroup.map { WatchVariantDescriptor(variantName: $0.name).selectionLabel }

        Menu {
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.entries) { entry in
                        Button {
                            selectColor(entry.colorGroup.id)
                        } label: {
                            variantRow(entry: entry, isSelected: selectedId == entry.colorGroup.id)
                        }
                    }
                }
            }
        } label: {
            Text(selectionLabel ?? "Watch style")
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .menuStyle(.button)
        .help("Watch style")
    }

    private func variantRow(entry: VariantEntry, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.colorGroup.frames.first?.icon ?? "applewatch")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.descriptor.title)
                if let subtitle = entry.descriptor.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func selectColor(_ colorGroupId: String) {
        guard let frame = DeviceFrameCatalog.variant(
            forFrameId: selectedFrame.id,
            colorGroupId: colorGroupId
        ) else { return }
        onSelectFrame(frame)
    }
}

private struct DeviceFrameColorSelector: View {
    let group: DeviceFrameGroup
    let selectedFrame: DeviceFrame
    let compact: Bool
    let onSelectFrame: (DeviceFrame) -> Void

    private var selectedColorGroupId: String? {
        DeviceFrameCatalog.colorGroup(forFrameId: selectedFrame.id)?.id
    }

    var body: some View {
        chipRow
    }

    private var chipRow: some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(group.colorGroups) { colorGroup in
                colorButton(for: colorGroup)
            }
        }
    }

    private func colorButton(for colorGroup: DeviceFrameColorGroup) -> some View {
        Button {
            selectColor(colorGroup.id)
        } label: {
            DeviceFrameColorChip(
                colorGroup: colorGroup,
                isSelected: selectedColorGroupId == colorGroup.id,
                compact: compact
            )
        }
        .buttonStyle(.plain)
        .help(colorGroup.name)
    }

    private func selectColor(_ colorGroupId: String) {
        guard let frame = DeviceFrameCatalog.variant(
            forFrameId: selectedFrame.id,
            colorGroupId: colorGroupId
        ) else { return }
        onSelectFrame(frame)
    }
}

private struct DeviceFrameColorChip: View {
    let colorGroup: DeviceFrameColorGroup
    let isSelected: Bool
    let compact: Bool

    var body: some View {
        if compact {
            compactChip
        } else {
            expandedChip
        }
    }

    private var expandedChip: some View {
        HStack(spacing: 8) {
            swatch(size: 18)
            Text(colorGroup.name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isSelected ? 1 : 0.5)
        )
    }

    private func swatch(size: CGFloat) -> some View {
        ZStack {
            if let swatch = colorGroup.swatch {
                Circle()
                    .fill(swatch)
            } else if let frameImageName = colorGroup.frames.first?.imageName {
                Image(frameImageName)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.16))
            }
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
        )
    }

    private var borderColor: Color {
        if isSelected {
            return .accentColor
        }
        return colorGroup.swatch == nil ? Color.secondary.opacity(0.35) : Color.primary.opacity(0.18)
    }

    private var compactChip: some View {
        swatch(size: 16)
    }
}
