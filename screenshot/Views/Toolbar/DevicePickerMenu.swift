import SwiftUI

/// Reusable device picker menu with "No device" option, used in both
/// the inspector panel (per-row default) and app settings (global default).
struct DevicePickerMenu: View {
    let category: DeviceCategory?
    let frameId: String?
    let onSelectNone: () -> Void
    let onSelectCategory: (DeviceCategory) -> Void
    let onSelectFrame: (DeviceFrame) -> Void

    var body: some View {
        Menu {
            Button {
                onSelectNone()
            } label: {
                Label("No device", systemImage: "rectangle.dashed")
            }

            Divider()

            DeviceMenuContent(
                onSelectCategory: onSelectCategory,
                onSelectFrame: onSelectFrame
            )
        } label: {
            HStack(spacing: 6) {
                Image(systemName: resolvedIcon)
                Text(resolvedLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Resolved display values

    private var resolvedFrame: DeviceFrame? {
        frameId.flatMap { DeviceFrameCatalog.frame(for: $0) }
    }

    private var resolvedLabel: String {
        if let frame = resolvedFrame {
            return "\(frame.modelName) - \(frame.shortLabel)"
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
}
