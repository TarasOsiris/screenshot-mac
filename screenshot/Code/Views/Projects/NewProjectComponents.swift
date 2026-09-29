import SwiftUI

enum NewProjectCreationMode: Hashable {
    case blank
    case template
}

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
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
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
            .overlay { cardBorder }
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
    let onActivate: (ProjectTemplate) -> Void

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
                        spacing: spacing,
                        onActivate: onActivate
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
                    spacing: spacing,
                    onActivate: nil
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
    /// Double-click creates, as in Finder's and Sketch's template pickers; iPad has no equivalent.
    let onActivate: ((ProjectTemplate) -> Void)?

    /// Templates arrive sorted by category, so grouping keeps that order.
    private var sections: [(category: TemplateCategory?, templates: [ProjectTemplate])] {
        var result: [(category: TemplateCategory?, templates: [ProjectTemplate])] = []
        for template in templates {
            if let last = result.indices.last, result[last].category == template.category {
                result[last].templates.append(template)
            } else {
                result.append((template.category, [template]))
            }
        }
        return result
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
            ForEach(sections, id: \.category) { section in
                Section {
                    ForEach(section.templates) { template in
                        card(for: template)
                    }
                } header: {
                    TemplateCategoryHeader(category: section.category)
                }
            }
        }
    }

    private func card(for template: ProjectTemplate) -> some View {
        Button {
            selectTemplate(template)
        } label: {
            TemplateSelectionCard(
                template: template,
                isSelected: selectedTemplateId == template.id
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            guard let onActivate else { return }
            selectTemplate(template)
            onActivate(template)
        })
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

private struct TemplateSelectionCard: View {
    let template: ProjectTemplate
    let isSelected: Bool
    @State private var isHovered = false

    private var borderColor: Color {
        if isSelected {
            return Color.accentColor
        }
        #if DEBUG
        if template.isIncludedInReleaseBuild {
            return Color.green.opacity(0.55)
        }
        #endif
        return Color.secondary.opacity(isHovered ? 0.35 : 0.12)
    }

    private var borderWidth: CGFloat {
        isSelected ? 2 : 1
    }

    /// Most templates cover every store device; only call out the ones that don't.
    private var deviceNote: String? {
        let everyStoreDevice: Set<DeviceFrameFamily> = [.iphone, .ipad, .android]
        guard !everyStoreDevice.isSubset(of: Set(template.deviceFamilies)) else { return nil }
        return template.deviceFamilies.map(\.rawValue).joined(separator: " · ")
    }

    // Fixed so every card in the grid lines up, whatever the preview image's own shape.
    private let previewAspectRatio: CGFloat = 266.0 / 144.0

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
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(template.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let deviceNote {
                    Text(verbatim: deviceNote)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(8)
        .onHover { isHovered = $0 }
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

private struct TemplateCategoryHeader: View {
    let category: TemplateCategory?

    var body: some View {
        Group {
            if let category {
                Text(category.title)
            } else {
                Text("More")
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }
}
