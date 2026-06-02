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
    let onToggleCollapsed: () -> Void
    let onStartLabelEdit: () -> Void
    let onCommitLabelEdit: () -> Void
    let onCancelLabelEdit: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDuplicate: () -> Void
    let onReset: () -> Void
    let onDelete: () -> Void
    let isPreviewMode: Bool
    let onTogglePreview: () -> Void
    let rowMenuContent: () -> RowMenuContent

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: row.isCollapsed ? "chevron.right" : "chevron.down")
                #if os(macOS)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 12, height: 12)
                #else
                .font(.system(size: 15, weight: .medium))
                .frame(width: 28, height: UIMetrics.ActionButton.frameSize)
                #endif
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggleCollapsed)

            if isEditingLabel {
                TextField("Row label", text: $editingLabelText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .frame(minWidth: 60, maxWidth: 200)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.platformControlBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .focused(isLabelFieldFocused)
                    .onSubmit { onCommitLabelEdit() }
                    .onChange(of: isLabelFieldFocused.wrappedValue) {
                        if !isLabelFieldFocused.wrappedValue { onCommitLabelEdit() }
                    }
                    #if os(macOS)
                    .onExitCommand { onCancelLabelEdit() }
                    #endif
            } else {
                Text(row.displayLabel)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : .secondary)
                    .opacity(row.label.isEmpty ? 0.5 : 1)
                    // iPad's narrow portrait canvas would wrap a long label to multiple lines.
                    #if os(iOS)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    #endif
                    .onTapGesture(count: 2, perform: onStartLabelEdit)
            }

            Text(verbatim: row.resolutionLabel)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { isPreviewMode },
                set: { newValue in
                    if newValue != isPreviewMode { onTogglePreview() }
                }
            )) {
                Image(systemName: "pencil").tag(false)
                Image(systemName: "eye").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            #if os(macOS)
            .controlSize(.small)
            #endif
            .fixedSize()
            .help(isPreviewMode ? "Switch to Edit" : "Switch to Preview")

            Spacer()

            HStack(spacing: 4) {
                RowHeaderActionButtons(
                    isSelected: isSelected,
                    canMoveUp: canMoveUp,
                    canMoveDown: canMoveDown,
                    canDelete: canDelete,
                    onMoveUp: onMoveUp,
                    onMoveDown: onMoveDown,
                    onDuplicate: onDuplicate,
                    onReset: onReset,
                    onDelete: onDelete
                )
                Menu {
                    rowMenuContent()
                } label: {
                    Image(systemName: "ellipsis.circle")
                        #if os(macOS)
                        .font(.system(size: 13))
                        #else
                        .font(.system(size: 20))
                        .frame(width: UIMetrics.ActionButton.frameSize, height: UIMetrics.ActionButton.frameSize)
                        #endif
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .opacity(isSelected ? 1 : 0.65)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

/// Isolates hover state so it doesn't re-render the parent header. Rebuilding
/// the header's `Menu` while a submenu is open causes macOS to dismiss it.
private struct RowHeaderActionButtons: View {
    let isSelected: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canDelete: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDuplicate: () -> Void
    let onReset: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            ActionButton(icon: "chevron.up", tooltip: "Move up", disabled: !canMoveUp, action: onMoveUp)
            ActionButton(icon: "chevron.down", tooltip: "Move down", disabled: !canMoveDown, action: onMoveDown)
            ActionButton(icon: "doc.on.doc", tooltip: "Duplicate row", disabled: false, action: onDuplicate)
            ActionButton(icon: "arrow.counterclockwise", tooltip: "Reset row", isDestructive: true, disabled: false, action: onReset)
            ActionButton(icon: "trash", tooltip: "Delete row", isDestructive: true, disabled: !canDelete, action: onDelete)
        }
        .opacity(isSelected || isHovered ? 1 : 0.65)
        .animation(.easeInOut(duration: 0.15), value: isSelected || isHovered)
        .onHover { isHovered = $0 }
    }
}
