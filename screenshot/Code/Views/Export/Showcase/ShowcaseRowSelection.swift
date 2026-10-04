import SwiftUI

struct ShowcaseRowsSection: View {
    let candidateRows: [ScreenshotRow]
    @Binding var selectedRowIds: Set<UUID>
    @Binding var excludedTemplateIds: Set<UUID>

    private var allSelected: Bool {
        selectedRowIds.count == candidateRows.count
    }

    var body: some View {
        // A single row has no row-level selection to make — surface its screenshots directly.
        if candidateRows.count == 1, let row = candidateRows.first {
            ShowcaseScreenshotsSection(row: row, excludedTemplateIds: $excludedTemplateIds)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                header
                VStack(spacing: 2) {
                    ForEach(candidateRows) { row in
                        ShowcaseRowToggle(
                            row: row,
                            selectedRowIds: $selectedRowIds,
                            excludedTemplateIds: $excludedTemplateIds
                        )
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            ShowcaseSectionTitle(text: "Rows", systemImage: "rectangle.stack")
            Spacer()
            Button(allSelected ? "None" : "All", action: toggleAllRows)
                .buttonStyle(.borderless)
                .scaledFont(UIMetrics.FontSize.inlineLabel, weight: .semibold)
        }
    }

    private func toggleAllRows() {
        selectedRowIds = allSelected ? [] : Set(candidateRows.map(\.id))
    }
}

/// Single-row variant: toggle individual screenshots on/off directly, with no
/// redundant row checkbox. Excluding every screenshot leaves nothing to export,
/// which disables the Export button (`ShowcaseExportSelection.selectedRowsOrdered` drops empty rows).
private struct ShowcaseScreenshotsSection: View {
    let row: ScreenshotRow
    @Binding var excludedTemplateIds: Set<UUID>

    private var allIncluded: Bool {
        row.templates.allSatisfy { !excludedTemplateIds.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ShowcaseSectionTitle(text: "Screenshots", systemImage: "photo.on.rectangle")
                Spacer()
                Button(allIncluded ? "None" : "All", action: toggleAll)
                    .buttonStyle(.borderless)
                    .scaledFont(UIMetrics.FontSize.inlineLabel, weight: .semibold)
            }
            ShowcaseTemplateChipStrip(templates: row.templates, excludedTemplateIds: $excludedTemplateIds)
        }
    }

    private func toggleAll() {
        if allIncluded {
            excludedTemplateIds.formUnion(row.templates.map(\.id))
        } else {
            row.templates.forEach { excludedTemplateIds.remove($0.id) }
        }
    }
}

private struct ShowcaseTemplateChipStrip: View {
    let templates: [ScreenshotTemplate]
    @Binding var excludedTemplateIds: Set<UUID>

    var body: some View {
        HStack(spacing: 4) {
            ForEach(templates.indices, id: \.self) { index in
                ShowcaseTemplateChip(
                    index: index,
                    template: templates[index],
                    excludedTemplateIds: $excludedTemplateIds
                )
            }
        }
    }
}

private struct ShowcaseRowToggle: View {
    let row: ScreenshotRow
    @Binding var selectedRowIds: Set<UUID>
    @Binding var excludedTemplateIds: Set<UUID>

    private var rowSelected: Bool {
        selectedRowIds.contains(row.id)
    }

    private var includedCount: Int {
        row.templates.count(where: { !excludedTemplateIds.contains($0.id) })
    }

    private var selectionBinding: Binding<Bool> {
        Binding(
            get: { rowSelected },
            set: { isOn in
                if isOn { selectedRowIds.insert(row.id) } else { selectedRowIds.remove(row.id) }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: selectionBinding) {
                HStack(spacing: 8) {
                    Text(row.displayLabel)
                        .scaledFont(UIMetrics.FontSize.menuRow)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text("\(includedCount)/\(row.templates.count)")
                        .scaledFont(UIMetrics.FontSize.inlineLabel)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            #if os(macOS)
            .toggleStyle(.checkbox)
            #endif

            if rowSelected, row.templates.count > 1 {
                ShowcaseTemplateChipStrip(templates: row.templates, excludedTemplateIds: $excludedTemplateIds)
                    .padding(.leading, 18)
            }
        }
        .padding(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 6))
    }
}

private struct ShowcaseTemplateChip: View {
    let index: Int
    let template: ScreenshotTemplate
    @Binding var excludedTemplateIds: Set<UUID>

    private var included: Bool {
        !excludedTemplateIds.contains(template.id)
    }

    var body: some View {
        Button(action: toggleIncluded) {
            Text("\(index + 1)")
                .scaledFont(UIMetrics.FontSize.inlineLabel, weight: .medium)
                .monospacedDigit()
                .frame(width: 20, height: 18)
                .background(chipShape.fill(chipFill))
                .overlay { chipShape.strokeBorder(chipStroke, lineWidth: UIMetrics.BorderWidth.hairline) }
                .foregroundStyle(included ? Color.accentColor : Color.secondary)
                .opacity(included ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .help(included ? "Exclude screenshot \(index + 1)" : "Include screenshot \(index + 1)")
    }

    private var chipShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip, style: .continuous)
    }

    private var chipFill: Color {
        included
            ? Color.accentColor.opacity(UIMetrics.Opacity.accentBadge)
            : Color.primary.opacity(UIMetrics.Opacity.sectionFill)
    }

    private var chipStroke: Color {
        included
            ? Color.accentColor.opacity(UIMetrics.Opacity.accentBorder)
            : Color.primary.opacity(UIMetrics.Opacity.sectionBorder)
    }

    private func toggleIncluded() {
        if included {
            excludedTemplateIds.insert(template.id)
        } else {
            excludedTemplateIds.remove(template.id)
        }
    }
}
