import SwiftUI

struct ContentExportControl<MenuContent: View>: View {
    let isExporting: Bool
    let exportSuccess: Bool
    let buttonText: String
    let helpText: String
    let isDisabled: Bool
    let onExport: () -> Void
    let menuContent: MenuContent

    init(
        isExporting: Bool,
        exportSuccess: Bool,
        buttonText: String,
        helpText: String,
        isDisabled: Bool,
        onExport: @escaping () -> Void,
        @ViewBuilder menuContent: () -> MenuContent
    ) {
        self.isExporting = isExporting
        self.exportSuccess = exportSuccess
        self.buttonText = buttonText
        self.helpText = helpText
        self.isDisabled = isDisabled
        self.onExport = onExport
        self.menuContent = menuContent()
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onExport) {
                buttonLabel
            }
            .keyboardShortcut("e", modifiers: .command)
            .help(helpText)

            Rectangle()
                .fill(.white.opacity(0.3))
                .frame(width: 1, height: 16)

            Menu {
                menuContent
            } label: {
                Label {
                    Text("")
                } icon: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 16, height: 22)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Export options")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(isDisabled)
    }

    private var buttonLabel: some View {
        HStack(spacing: 4) {
            if isExporting {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            } else if exportSuccess {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
            } else {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 11))
            }
            Text(buttonText)
        }
    }
}
