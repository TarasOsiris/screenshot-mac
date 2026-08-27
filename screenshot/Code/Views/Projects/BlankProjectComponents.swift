import SwiftUI

private let maxBlankProjectRows = 8

private extension Array where Element == BlankProjectRowDraft {
    /// Appends a row unless the blank-project cap is reached. Shared by the macOS configurator
    /// and the iPad section, which had this written out twice.
    mutating func appendBlankRow() {
        guard count < maxBlankProjectRows else { return }
        append(BlankProjectRowDraft())
    }
}

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
            Button(action: { rowDrafts.appendBlankRow() }) {
                Image(systemName: "plus")
            }
            .disabled(rowDrafts.count >= maxBlankProjectRows)
            .accessibilityLabel("Add Row")
        }
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

            Button(action: { rowDrafts.appendBlankRow() }) {
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
            .compactControlSize()
            .disabled(rowDrafts.count >= maxBlankProjectRows)
            .accessibilityLabel("Add Row")
        }
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
        let storedCount = UserDefaults.standard.integer(forKey: AppSettingsKeys.defaultTemplateCount)
        self.templateCount = storedCount > 0 ? storedCount : AppSettingsKeys.Default.defaultTemplateCount
        self.deviceCategory = category
        if let category {
            self.sizePreset = category.suggestedSizePreset
            self.deviceFrameId = DeviceFrameCatalog.firstPortraitFrameId(for: category)
        } else {
            self.sizePreset = UserDefaults.standard.string(forKey: AppSettingsKeys.defaultScreenshotSize) ?? AppSettingsKeys.Default.defaultScreenshotSize
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
