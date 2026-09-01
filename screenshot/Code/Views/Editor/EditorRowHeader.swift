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

    @Environment(\.editorViewportWidth) private var editorViewportWidth

    private var showsLabels: Bool {
        // Don't let the fit fallback hide the field mid-rename.
        guard !isEditingLabel else { return true }
        let label = EditorRowHeaderLayout.textWidth(
            row.displayLabel,
            size: 12,
            weight: isSelected ? .semibold : .medium
        )
        let resolution = EditorRowHeaderLayout.textWidth(row.resolutionLabel, size: 10, weight: .regular)
        return EditorRowHeaderLayout.showsLabels(
            availableWidth: editorViewportWidth,
            // The two runs sit either side of one 8pt gap.
            labelsWidth: label + 8 + resolution
        )
    }

    var body: some View {
        headerContent(showLabels: showsLabels)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func headerContent(showLabels: Bool) -> some View {
        HStack(spacing: 8) {
            chevron

            if showLabels {
                labelView

                Text(verbatim: row.resolutionLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            previewToggle

            Spacer()

            trailingControls
        }
    }

    private var chevron: some View {
        Button(action: onToggleCollapsed) {
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
        }
        .buttonStyle(EditorIconButtonStyle())
        .accessibilityLabel(row.isCollapsed ? Text("Expand") : Text("Collapse"))
    }

    @ViewBuilder
    private var labelView: some View {
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
                .submitLabel(.done)
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
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .opacity(row.label.isEmpty ? 0.5 : 1)
                .lineLimit(1)
                .fixedSize()
                .onTapGesture(count: 2, perform: onStartLabelEdit)
        }
    }

    /// Hand-drawn rather than a `Picker(.segmented)`, which is an `NSSegmentedControl`: one per row,
    /// and instantiating them was ~10% of the one freeze left in a scroll trace.
    private var previewToggle: some View {
        HStack(spacing: 0) {
            previewSegment("pencil", isSelected: !isPreviewMode, label: "Switch to Edit") {
                if isPreviewMode { onTogglePreview() }
            }
            previewSegment("eye", isSelected: isPreviewMode, label: "Switch to Preview") {
                if !isPreviewMode { onTogglePreview() }
            }
        }
        .padding(1)
        .background {
            RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip, style: .continuous)
                .fill(Color.primary.opacity(UIMetrics.Opacity.sectionFill))
                .overlay {
                    RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip, style: .continuous)
                        .strokeBorder(UIMetrics.Stroke.subtle)
                }
        }
        .fixedSize()
    }

    private func previewSegment(
        _ icon: String,
        isSelected: Bool,
        label: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: UIMetrics.ActionButton.iconSize))
                #if os(macOS)
                .frame(width: 24, height: 16)
                #else
                .frame(width: 40, height: UIMetrics.ActionButton.frameSize - 8)
                #endif
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip - 1, style: .continuous)
                            .fill(Color.primary.opacity(UIMetrics.Opacity.hairlineOverlay))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(EditorIconButtonStyle())
        .focusable(false)
        .accessibilityLabel(label)
        // The `Picker` this replaced conveyed which mode was active; keep that for VoiceOver.
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(label)
    }

    private var trailingControls: some View {
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
            .accessibilityLabel("More actions")
            .opacity(isSelected ? 1 : 0.65)
        }
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

    #if os(macOS)
    @State private var isHovered = false
    #endif

    var body: some View {
        HStack(spacing: 4) {
            ActionButton(icon: "chevron.up", tooltip: "Move up", disabled: !canMoveUp, action: onMoveUp)
            ActionButton(icon: "chevron.down", tooltip: "Move down", disabled: !canMoveDown, action: onMoveDown)
            ActionButton(icon: "doc.on.doc", tooltip: "Duplicate row", disabled: false, action: onDuplicate)
            ActionButton(icon: "arrow.counterclockwise", tooltip: "Reset row", isDestructive: true, disabled: false, action: onReset)
            ActionButton(icon: "trash", tooltip: "Delete row", isDestructive: true, disabled: !canDelete, action: onDelete)
        }
        // iPad has no hover to reveal these, so keep them full-strength; macOS dims until hover/selection.
        #if os(macOS)
        .opacity(isSelected || isHovered ? 1 : 0.65)
        .animation(.easeInOut(duration: 0.15), value: isSelected || isHovered)
        .onHover { isHovered = $0 }
        #endif
    }
}
