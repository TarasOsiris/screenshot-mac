import SwiftUI

enum NewProjectCreationMode: Hashable {
    case blank
    case template
}

private let maxBlankProjectRows = 8

struct NewProjectModePicker: View {
    @Binding var selectedMode: NewProjectCreationMode

    var body: some View {
        HStack(spacing: 12) {
            NewProjectModeCard(
                title: "Template",
                subtitle: "Pre-designed layouts",
                icon: "square.grid.2x2",
                mode: .template,
                selectedMode: $selectedMode
            )
            NewProjectModeCard(
                title: "Blank",
                subtitle: "Set up your own rows",
                icon: "square.on.square.dashed",
                mode: .blank,
                selectedMode: $selectedMode
            )
        }
    }
}

private struct NewProjectModeCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let mode: NewProjectCreationMode
    @Binding var selectedMode: NewProjectCreationMode

    private var isSelected: Bool {
        selectedMode == mode
    }

    var body: some View {
        Button(action: selectMode) {
            HStack(spacing: 12) {
                iconBackground
                titleStack
                Spacer()
                if isSelected { selectedIcon }
            }
            .padding(14)
            .background(Color.platformWindowBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(cardBorder)
        }
        .buttonStyle(.plain)
    }

    private var iconBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.1))
            .frame(width: 38, height: 38)
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
    }

    private var titleStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var selectedIcon: some View {
        Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(Color.accentColor)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(
                isSelected ? Color.accentColor : Color.secondary.opacity(0.12),
                lineWidth: isSelected ? 2 : 1
            )
    }

    private func selectMode() {
        selectedMode = mode
    }
}

struct NewProjectTemplateConfigurator: View {
    let templates: [ProjectTemplate]
    @Binding var selectedTemplateId: String?
    let columns: [GridItem]
    let spacing: CGFloat
    let horizontalPadding: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose a template")
                .font(.headline)

            #if DEBUG
            if !templates.isEmpty {
                NewProjectReleaseTemplateLegend()
            }
            #endif

            if templates.isEmpty {
                NewProjectNoTemplatesView()
            } else {
                ScrollView {
                    NewProjectTemplateGrid(
                        templates: templates,
                        selectedTemplateId: $selectedTemplateId,
                        columns: columns,
                        spacing: spacing
                    )
                    .padding(.horizontal, horizontalPadding)
                }
            }
        }
    }
}

#if os(iOS)
struct NewProjectTemplateSection: View {
    let templates: [ProjectTemplate]
    @Binding var selectedTemplateId: String?
    let columns: [GridItem]
    let spacing: CGFloat

    var body: some View {
        Section {
            if templates.isEmpty {
                NewProjectNoTemplatesView()
            } else {
                NewProjectTemplateGrid(
                    templates: templates,
                    selectedTemplateId: $selectedTemplateId,
                    columns: columns,
                    spacing: spacing
                )
                .padding(.vertical, 6)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)
            }
        } header: {
            Text("Choose a Template")
        } footer: {
            #if DEBUG
            if !templates.isEmpty {
                Text("Outlined templates are included in non-debug builds.")
            }
            #endif
        }
    }
}
#endif

private struct NewProjectTemplateGrid: View {
    let templates: [ProjectTemplate]
    @Binding var selectedTemplateId: String?
    let columns: [GridItem]
    let spacing: CGFloat

    var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(templates) { template in
                Button {
                    selectTemplate(template)
                } label: {
                    TemplateSelectionCard(
                        template: template,
                        isSelected: selectedTemplateId == template.id
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func selectTemplate(_ template: ProjectTemplate) {
        selectedTemplateId = template.id
    }
}

private struct NewProjectNoTemplatesView: View {
    var body: some View {
        ContentUnavailableView(
            "No Templates Available",
            systemImage: "square.grid.2x2",
            description: Text("Add templates to the app bundle.")
        )
    }
}

#if DEBUG
private struct NewProjectReleaseTemplateLegend: View {
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.green.opacity(0.55), lineWidth: 2)
                .frame(width: 18, height: 14)

            Text("Outlined templates are included in non-debug builds.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
#endif

#if os(iOS)
struct BlankProjectSection: View {
    @Binding var rowDrafts: [BlankProjectRowDraft]

    var body: some View {
        Section {
            BlankProjectRowsList(rowDrafts: $rowDrafts, usesFormInsets: true)
        } header: {
            header
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Rows")
            Spacer()
            if rowDrafts.count > 1 {
                EditButton()
                    .textCase(nil)
            }
            Button(action: addRow) {
                Image(systemName: "plus")
            }
            .disabled(rowDrafts.count >= maxBlankProjectRows)
            .accessibilityLabel("Add Row")
        }
    }

    private func addRow() {
        guard rowDrafts.count < maxBlankProjectRows else { return }
        rowDrafts.append(BlankProjectRowDraft())
    }
}
#endif

struct BlankProjectConfigurator: View {
    @Binding var rowDrafts: [BlankProjectRowDraft]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            List {
                BlankProjectRowsList(rowDrafts: $rowDrafts, usesFormInsets: false)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var header: some View {
        HStack {
            Text("Rows")
                .font(.headline)

            Spacer()

            Button(action: addRow) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.secondary.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .disabled(rowDrafts.count >= maxBlankProjectRows)
        }
    }

    private func addRow() {
        guard rowDrafts.count < maxBlankProjectRows else { return }
        rowDrafts.append(BlankProjectRowDraft())
    }
}

private struct BlankProjectRowsList: View {
    @Binding var rowDrafts: [BlankProjectRowDraft]
    let usesFormInsets: Bool

    var body: some View {
        ForEach(rowDrafts) { draft in
            BlankProjectRowCard(
                draft: binding(for: draft.id),
                canDelete: rowDrafts.count > 1,
                canDuplicate: rowDrafts.count < maxBlankProjectRows,
                onDelete: { removeRow(id: draft.id) },
                onDuplicate: { duplicateRow(id: draft.id) }
            )
            .listRowSeparator(.hidden)
            .listRowInsets(rowInsets)
            .listRowBackground(Color.clear)
        }
        .onMove { source, destination in
            rowDrafts.move(fromOffsets: source, toOffset: destination)
        }
    }

    private var rowInsets: EdgeInsets {
        usesFormInsets
            ? EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
            : EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0)
    }

    private func binding(for id: UUID) -> Binding<BlankProjectRowDraft> {
        Binding {
            rowDrafts.first(where: { $0.id == id }) ?? BlankProjectRowDraft()
        } set: { updatedDraft in
            guard let index = rowDrafts.firstIndex(where: { $0.id == id }) else { return }
            rowDrafts[index] = updatedDraft
        }
    }

    private func removeRow(id: UUID) {
        guard rowDrafts.count > 1 else { return }
        rowDrafts.removeAll { $0.id == id }
    }

    private func duplicateRow(id: UUID) {
        guard rowDrafts.count < maxBlankProjectRows,
              let index = rowDrafts.firstIndex(where: { $0.id == id }) else { return }
        let source = rowDrafts[index]
        var copy = BlankProjectRowDraft()
        copy.sizePreset = source.sizePreset
        copy.templateCount = source.templateCount
        copy.deviceCategory = source.deviceCategory
        copy.deviceFrameId = source.deviceFrameId
        rowDrafts.insert(copy, at: index + 1)
    }
}

struct BlankProjectRowDraft: Identifiable, Equatable {
    let id = UUID()
    var sizePreset: String
    var templateCount: Int
    var deviceCategory: DeviceCategory?
    var deviceFrameId: String?

    init(category: DeviceCategory? = .iphone) {
        let storedCount = UserDefaults.standard.integer(forKey: "defaultTemplateCount")
        self.templateCount = storedCount > 0 ? storedCount : 3
        self.deviceCategory = category
        if let category {
            self.sizePreset = category.suggestedSizePreset
            self.deviceFrameId = DeviceFrameCatalog.firstPortraitFrameId(for: category)
        } else {
            self.sizePreset = UserDefaults.standard.string(forKey: "defaultScreenshotSize") ?? "1242x2688"
            self.deviceFrameId = nil
        }
    }

    var configuration: BlankProjectRowConfiguration {
        BlankProjectRowConfiguration(
            label: nil,
            sizePreset: sizePreset,
            templateCount: templateCount,
            deviceCategory: deviceCategory,
            deviceFrameId: deviceFrameId
        )
    }
}

private struct BlankProjectRowCard: View {
    @Binding var draft: BlankProjectRowDraft
    let canDelete: Bool
    let canDuplicate: Bool
    let onDelete: () -> Void
    let onDuplicate: () -> Void

    var body: some View {
        #if os(iOS)
        ViewThatFits(in: .horizontal) {
            horizontalContent
            verticalContent
        }
        #else
        horizontalContent
        #endif
    }

    private var horizontalContent: some View {
        HStack(alignment: .center, spacing: 14) {
            sizePicker
            templateCountControl
            devicePicker
            actionButtons
        }
        .rowCardChrome()
    }

    private var verticalContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            sizePicker
            HStack(spacing: 12) {
                templateCountControl
                devicePicker
            }
            actionButtons
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .rowCardChrome()
    }

    private var sizePicker: some View {
        ScreenshotSizePicker(selection: $draft.sizePreset, label: "Size")
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: draft.sizePreset) { _, newPreset in
                applySizePreset(newPreset)
            }
    }

    private var templateCountControl: some View {
        HStack(spacing: 4) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TemplateCountPicker(selection: $draft.templateCount, label: "")
                .labelsHidden()
        }
        .frame(width: 64)
        .help("Screenshots per row")
    }

    private var devicePicker: some View {
        DevicePickerMenu(
            category: draft.deviceCategory,
            frameId: draft.deviceFrameId,
            presentation: .inline,
            onSelectNone: {
                selectNoDevice()
            },
            onSelectCategory: { category in
                selectDeviceCategory(category)
            },
            onSelectFrame: { frame in
                selectDeviceFrame(frame)
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.system(size: 12))
    }

    private func applySizePreset(_ preset: String) {
        guard let category = DeviceCategory.suggestedCategory(forSizePreset: preset),
              category != draft.deviceCategory else { return }
        draft.deviceCategory = category
        draft.deviceFrameId = DeviceFrameCatalog.firstPortraitFrameId(for: category)
    }

    private func selectNoDevice() {
        draft.deviceCategory = nil
        draft.deviceFrameId = nil
    }

    private func selectDeviceCategory(_ category: DeviceCategory) {
        draft.deviceCategory = category
        draft.deviceFrameId = nil
        draft.sizePreset = category.suggestedSizePreset
    }

    private func selectDeviceFrame(_ frame: DeviceFrame) {
        draft.deviceCategory = frame.fallbackCategory
        draft.deviceFrameId = frame.id
        if let preset = DeviceFrameCatalog.suggestedSizePreset(forFrameId: frame.id) {
            draft.sizePreset = preset
        }
    }

    private var actionButtons: some View {
        #if os(iOS)
        HStack(spacing: 8) {
            rowActionButton(
                icon: "doc.on.doc",
                accessibilityLabel: "Duplicate row",
                disabled: !canDuplicate,
                action: onDuplicate
            )

            rowActionButton(
                icon: "trash",
                accessibilityLabel: "Delete row",
                disabled: !canDelete,
                role: .destructive,
                action: onDelete
            )
        }
        #else
        HStack(spacing: 4) {
            Button(action: onDuplicate) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .disabled(!canDuplicate)
            .help("Duplicate row")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .disabled(!canDelete)
            .help("Delete row")
        }
        #endif
    }

    #if os(iOS)
    private func rowActionButton(
        icon: String,
        accessibilityLabel: LocalizedStringKey,
        disabled: Bool,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .disabled(disabled)
        .accessibilityLabel(accessibilityLabel)
    }
    #endif
}

private extension View {
    func rowCardChrome() -> some View {
        padding(14)
            .background(Color.platformControlBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct TemplateSelectionCard: View {
    let template: ProjectTemplate
    let isSelected: Bool

    private var borderColor: Color {
        if isSelected {
            return Color.accentColor
        }
        #if DEBUG
        if template.isIncludedInReleaseBuild {
            return Color.green.opacity(0.55)
        }
        #endif
        return Color.secondary.opacity(0.12)
    }

    private var borderWidth: CGFloat {
        isSelected ? 2 : 1
    }

    private var previewAspectRatio: CGFloat {
        guard let size = template.previewImage?.size, size.height > 0 else { return 266.0 / 144.0 }
        return size.width / size.height
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.secondary.opacity(0.12)
                .aspectRatio(previewAspectRatio, contentMode: .fit)
                .overlay {
                    if let previewImage = template.previewImage {
                        Image(nsImage: previewImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(template.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(8)
        .background(
            cardBackgroundColor,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        }
    }

    private var cardBackgroundColor: Color {
        #if DEBUG
        if template.isIncludedInReleaseBuild && !isSelected {
            return Color.green.opacity(0.05)
        }
        #endif
        return Color.platformControlBackground
    }
}
