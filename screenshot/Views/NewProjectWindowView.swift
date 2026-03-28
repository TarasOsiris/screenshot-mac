import SwiftUI

struct NewProjectWindowView: View {
    static let windowID = "new-project"
    private let templateGridSpacing: CGFloat = 12
    private let templateGridHorizontalPadding: CGFloat = 8

    @Environment(AppState.self) private var state
    @Environment(StoreService.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var projectName = ""
    @State private var creationMode: CreationMode = .blank
    @State private var selectedTemplateId: String?
    @State private var rowDrafts: [BlankProjectRowDraft] = []
    @State private var templates: [ProjectTemplate] = []
    @FocusState private var isNameFieldFocused: Bool

    private var selectedTemplate: ProjectTemplate? {
        guard let selectedTemplateId else { return nil }
        return templates.first(where: { $0.id == selectedTemplateId })
    }

    private var createButtonTitle: String {
        creationMode == .blank ? "Create Blank Project" : "Create from Template"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                projectNameField
                modePicker

                Group {
                    switch creationMode {
                    case .blank:
                        blankProjectConfigurator
                    case .template:
                        templateConfigurator
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: creationMode)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(18)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            footer
        }
        .padding(22)
        .frame(minWidth: 760, idealWidth: 760, minHeight: 620, idealHeight: 620)
        .onAppear {
            templates = TemplateService.availableTemplates()
            projectName = "Project \(state.visibleProjects.count + 1)"
            creationMode = .blank
            selectedTemplateId = templates.first?.id
            rowDrafts = [
                BlankProjectRowDraft(category: .iphone),
                BlankProjectRowDraft(category: .ipadPro13),
                BlankProjectRowDraft(category: .androidPhone),
            ]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isNameFieldFocused = true
            }
        }
    }

    private var projectNameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Name")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Project name", text: $projectName)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFieldFocused)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 12) {
            modeCard(
                title: "Blank",
                subtitle: "Rows + devices",
                icon: "square.on.square.dashed",
                mode: .blank
            )
            modeCard(
                title: "Template",
                subtitle: "Pick a layout",
                icon: "square.grid.2x2",
                mode: .template
            )
        }
    }

    private var blankProjectConfigurator: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Configure rows")
                    .font(.headline)

                Spacer()

                Button {
                    addRow()
                } label: {
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
                .disabled(rowDrafts.count >= 8)
            }

            List {
                ForEach(rowDrafts) { draft in
                    BlankProjectRowCard(
                        draft: binding(for: draft.id),
                        canDelete: rowDrafts.count > 1,
                        canDuplicate: rowDrafts.count < 8,
                        onDelete: {
                            removeRow(id: draft.id)
                        },
                        onDuplicate: {
                            duplicateRow(id: draft.id)
                        }
                    )
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                }
                .onMove { source, destination in
                    rowDrafts.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var templateConfigurator: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Template")
                .font(.headline)

            if templates.isEmpty {
                ContentUnavailableView(
                    "No Templates Available",
                    systemImage: "square.grid.2x2",
                    description: Text("Add templates to the app bundle.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: templateGridColumns, spacing: templateGridSpacing) {
                        ForEach(templates) { template in
                            Button {
                                selectedTemplateId = template.id
                            } label: {
                                TemplateSelectionCard(
                                    template: template,
                                    isSelected: selectedTemplateId == template.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, templateGridHorizontalPadding)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .keyboardShortcut(.escape)

            Spacer()

            Button(createButtonTitle) {
                createProject()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canCreateProject)
            .keyboardShortcut(.return)
        }
    }

    private var canCreateProject: Bool {
        switch creationMode {
        case .blank:
            !rowDrafts.isEmpty
        case .template:
            selectedTemplate != nil
        }
    }

    private var templateGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 130, maximum: 200), spacing: templateGridSpacing)]
    }

    private func binding(for id: UUID) -> Binding<BlankProjectRowDraft> {
        Binding {
            rowDrafts.first(where: { $0.id == id }) ?? BlankProjectRowDraft()
        } set: { updatedDraft in
            guard let index = rowDrafts.firstIndex(where: { $0.id == id }) else { return }
            rowDrafts[index] = updatedDraft
        }
    }

    private func addRow() {
        guard rowDrafts.count < 8 else { return }
        rowDrafts.append(BlankProjectRowDraft())
    }

    private func removeRow(id: UUID) {
        guard rowDrafts.count > 1 else { return }
        rowDrafts.removeAll { $0.id == id }
    }

    private func duplicateRow(id: UUID) {
        guard rowDrafts.count < 8,
              let index = rowDrafts.firstIndex(where: { $0.id == id }) else { return }
        let source = rowDrafts[index]
        var copy = BlankProjectRowDraft()
        copy.sizePreset = source.sizePreset
        copy.templateCount = source.templateCount
        copy.deviceCategory = source.deviceCategory
        copy.deviceFrameId = source.deviceFrameId
        rowDrafts.insert(copy, at: index + 1)
    }

    private func createProject() {
        store.requirePro(
            allowed: store.canCreateProject(),
            context: .projectLimit
        ) {
            let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = trimmedName.isEmpty ? "Project \(state.visibleProjects.count + 1)" : trimmedName

            switch creationMode {
            case .blank:
                let configurations = rowDrafts.map(\.configuration)
                state.createBlankProject(name: resolvedName, rowConfigurations: configurations)
            case .template:
                guard let selectedTemplate else { return }
                state.createProjectFromTemplate(selectedTemplate, name: resolvedName)
            }

            dismiss()
        }
    }

    private enum CreationMode: Hashable {
        case blank
        case template
    }

    private func modeCard(title: String, subtitle: String, icon: String, mode: CreationMode) -> some View {
        let isSelected = creationMode == mode
        return Button {
            creationMode = mode
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.1))
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(14)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }

}

private struct BlankProjectRowDraft: Identifiable, Equatable {
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
        HStack(alignment: .center, spacing: 14) {
            ScreenshotSizePicker(selection: $draft.sizePreset, label: "Size")
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: draft.sizePreset) { _, newPreset in
                    if let category = DeviceCategory.suggestedCategory(forSizePreset: newPreset),
                       category != draft.deviceCategory {
                        draft.deviceCategory = category
                        draft.deviceFrameId = DeviceFrameCatalog.firstPortraitFrameId(for: category)
                    }
                }

            HStack(spacing: 4) {
                Image(systemName: "rectangle.split.3x1")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TemplateCountPicker(selection: $draft.templateCount, label: "")
                    .labelsHidden()
            }
            .frame(width: 64)
            .help("Screenshots per row")

            DevicePickerMenu(
                    category: draft.deviceCategory,
                    frameId: draft.deviceFrameId,
                    onSelectNone: {
                        draft.deviceCategory = nil
                        draft.deviceFrameId = nil
                    },
                    onSelectCategory: { category in
                        draft.deviceCategory = category
                        draft.deviceFrameId = nil
                        draft.sizePreset = category.suggestedSizePreset
                    },
                    onSelectFrame: { frame in
                        draft.deviceCategory = frame.fallbackCategory
                        draft.deviceFrameId = frame.id
                        if let preset = DeviceFrameCatalog.suggestedSizePreset(forFrameId: frame.id) {
                            draft.sizePreset = preset
                        }
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.system(size: 12))

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
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct TemplateSelectionCard: View {
    let template: ProjectTemplate
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.secondary.opacity(0.12)
                .frame(height: 72)
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
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
        }
    }
}
