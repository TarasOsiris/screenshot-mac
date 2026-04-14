import SwiftUI

struct EditorRowHeader<RowMenuContent: View>: View {
    let row: ScreenshotRow
    let isSelected: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canDelete: Bool
    @Binding var isEditingLabel: Bool
    @Binding var editingLabelText: String
    var isLabelFieldFocused: FocusState<Bool>.Binding
    @Binding var isRowHovered: Bool
    let onToggleCollapsed: () -> Void
    let onStartLabelEdit: () -> Void
    let onCommitLabelEdit: () -> Void
    let onCancelLabelEdit: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDuplicate: () -> Void
    let onReset: () -> Void
    let onDelete: () -> Void
    let rowMenuContent: () -> RowMenuContent

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: row.isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 12, height: 12)
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggleCollapsed)

            if isEditingLabel {
                TextField("Row label", text: $editingLabelText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .frame(minWidth: 60, maxWidth: 200)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(4)
                    .focused(isLabelFieldFocused)
                    .onSubmit { onCommitLabelEdit() }
                    .onChange(of: isLabelFieldFocused.wrappedValue) {
                        if !isLabelFieldFocused.wrappedValue { onCommitLabelEdit() }
                    }
                    .onExitCommand { onCancelLabelEdit() }
            } else {
                Text(row.label.isEmpty ? "Untitled Row" : row.label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : .secondary)
                    .opacity(row.label.isEmpty ? 0.5 : 1)
                    .onTapGesture(count: 2, perform: onStartLabelEdit)
            }

            Text(verbatim: row.resolutionLabel)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 4) {
                ActionButton(icon: "chevron.up", tooltip: "Move up", disabled: !canMoveUp, action: onMoveUp)
                ActionButton(icon: "chevron.down", tooltip: "Move down", disabled: !canMoveDown, action: onMoveDown)
                ActionButton(icon: "doc.on.doc", tooltip: "Duplicate row", disabled: false, action: onDuplicate)
                ActionButton(icon: "arrow.counterclockwise", tooltip: "Reset row", isDestructive: true, disabled: false, action: onReset)
                ActionButton(icon: "trash", tooltip: "Delete row", isDestructive: true, disabled: !canDelete, action: onDelete)
                Menu {
                    rowMenuContent()
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .opacity(isSelected || isRowHovered ? 1 : 0.65)
            .animation(.easeInOut(duration: 0.15), value: isSelected || isRowHovered)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .onHover { isRowHovered = $0 }
    }
}
