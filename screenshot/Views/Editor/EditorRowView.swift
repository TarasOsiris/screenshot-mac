import SwiftUI

struct EditorRowView: View {
    @Bindable var state: AppState
    let row: ScreenshotRow

    private var isSelected: Bool {
        state.selectedRowId == row.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row header
            HStack(spacing: 8) {
                Circle()
                    .fill(isSelected ? .blue : .gray.opacity(0.4))
                    .frame(width: 6, height: 6)

                Text(row.label)
                    .font(.system(size: 12, weight: .medium))

                Text(verbatim: row.resolutionLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 4) {
                    rowActionButton("chevron.up", disabled: state.rows.first?.id == row.id) {
                        withAnimation(.easeInOut(duration: 0.2)) { state.moveRowUp(row.id) }
                    }
                    rowActionButton("chevron.down", disabled: state.rows.last?.id == row.id) {
                        withAnimation(.easeInOut(duration: 0.2)) { state.moveRowDown(row.id) }
                    }
                    rowActionButton("doc.on.doc", disabled: false) {
                        withAnimation(.easeInOut(duration: 0.2)) { state.duplicateRow(row.id) }
                    }
                    rowActionButton("trash", disabled: state.rows.count <= 1) {
                        withAnimation(.easeInOut(duration: 0.2)) { state.deleteRow(row.id) }
                    }
                }
                .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Template strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(row.templates.enumerated()), id: \.element.id) { index, template in
                        ScreenshotTemplateView(
                            template: template,
                            displayWidth: row.displayWidth,
                            displayHeight: row.displayHeight,
                            templateWidth: row.templateWidth,
                            templateHeight: row.templateHeight,
                            bgColor: row.bgColor,
                            index: index,
                            canDelete: row.templates.count > 1,
                            onDelete: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    state.removeTemplate(template.id, from: row.id)
                                }
                            }
                        )
                    }

                    // Add button
                    AddTemplateButton(width: row.displayWidth, height: row.displayHeight) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            state.addTemplate(to: row.id)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            state.selectedRowId = row.id
        }
        .background(isSelected ? Color.accentColor.opacity(0.04) : Color.clear)
    }

}

private struct AddTemplateButton: View {
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            .foregroundStyle(isHovered ? .primary : .secondary)
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.primary.opacity(isHovered ? 0.04 : 0))
            )
            .contentShape(Rectangle())
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: 20))
                    .foregroundStyle(isHovered ? .primary : .secondary)
            }
            .onHover { isHovered = $0 }
            .onTapGesture { action() }
            .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

extension EditorRowView {
    fileprivate func rowActionButton(_ icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? .tertiary : .secondary)
        .disabled(disabled)
    }
}
