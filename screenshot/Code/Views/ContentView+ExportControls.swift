import SwiftUI

extension ContentView {
    var exportControlGroup: some View {
        ContentExportControl(
            isExporting: exportFlow.isExporting,
            exportSuccess: exportFlow.exportSuccess,
            buttonText: exportButtonText,
            helpText: exportHelpText,
            isDisabled: exportFlow.isExporting || state.rows.isEmpty,
            onExport: { exportScreenshots() }
        ) {
            exportMenuContent
        }
        .coachPopover(step: .export, coach: state.coach, arrowEdge: .top)
    }

    #if os(iOS)
    @ViewBuilder
    var iPadExportControl: some View {
        let isDisabled = exportFlow.isExporting || state.rows.isEmpty
        Menu {
            Button("Export All Screenshots", systemImage: "square.and.arrow.up") {
                exportScreenshotsForIPad()
            }

            Menu("Export Rows", systemImage: "rectangle.3.group") {
                Button("Continuous", systemImage: "rectangle.split.3x1") {
                    exportRowImages()
                }
                Button("Showcase", systemImage: "rectangle.stack") {
                    exportShowcaseImages()
                }
            }

            if state.localeState.locales.count > 1 {
                Menu("Export Locale", systemImage: "globe") {
                    ForEach(state.localeState.locales) { locale in
                        Button(locale.flagLabel) {
                            exportScreenshotsForIPad(localeFilter: locale.code)
                        }
                    }
                }
            }

            Divider()

            Button("Upload to App Store Connect…", systemImage: "icloud.and.arrow.up") {
                showingASCUploadSheet = true
            }
            .disabled(state.rows.isEmpty)

            Button("Upload to Google Play…", systemImage: "play.rectangle.on.rectangle") {
                showingGooglePlayUploadSheet = true
            }
            .disabled(state.rows.isEmpty)
        } label: {
            iPadExportLabel
        }
        .iPadToolbarProminentStyle()
        .controlSize(.regular)
        .disabled(isDisabled)
        .coachPopoverAnchor(step: .export, coach: state.coach)
    }

    @ViewBuilder
    var iPadExportLabel: some View {
        if exportFlow.isExporting {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Exporting…")
            }
        } else {
            let done = exportFlow.exportSuccess
            // square.and.arrow.up renders high (reserves space for the up-arrow); nudge the glyph down to align it.
            Label {
                Text(done ? "Exported" : "Export")
            } icon: {
                Image(systemName: done ? "checkmark.circle.fill" : "square.and.arrow.up")
                    .offset(y: done ? 0 : -2)
            }
        }
    }
    #endif

    @ViewBuilder
    var exportMenuContent: some View {
        Button("Export All Screenshots to Folder...", systemImage: "square.and.arrow.up") {
            exportScreenshotsAs()
        }

        Menu("Export Rows", systemImage: "rectangle.3.group") {
            Button("Continuous", systemImage: "rectangle.split.3x1") {
                exportRowImages()
            }
            Button("Showcase", systemImage: "rectangle.stack") {
                exportShowcaseImages()
            }
        }
        .disabled(state.rows.isEmpty)

        if state.localeState.locales.count > 1 {
            Menu("Export Locale", systemImage: "globe") {
                ForEach(state.localeState.locales) { locale in
                    Button(locale.flagLabel) {
                        exportScreenshots(localeFilter: locale.code)
                    }
                }
            }
            .disabled(state.rows.isEmpty)
        }

        if hasLastExportDestination {
            Button("Open Export Folder", systemImage: "folder") {
                openLastExportFolder()
            }

            Divider()

            Text("Current export folder: \(lastExportFolderName)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }

        #if os(macOS)
        Divider()

        Button("Upload to App Store Connect…", systemImage: "icloud.and.arrow.up") {
            showingASCUploadSheet = true
        }
        .disabled(state.rows.isEmpty)

        Button("Upload to Google Play…", systemImage: "play.rectangle.on.rectangle") {
            showingGooglePlayUploadSheet = true
        }
        .disabled(state.rows.isEmpty)
        #endif
    }
}

struct ContentExportControl<MenuContent: View>: View {
    let isExporting: Bool
    let exportSuccess: Bool
    let buttonText: LocalizedStringKey
    let helpText: LocalizedStringKey
    let isDisabled: Bool
    let onExport: () -> Void
    let menuContent: MenuContent

    init(
        isExporting: Bool,
        exportSuccess: Bool,
        buttonText: LocalizedStringKey,
        helpText: LocalizedStringKey,
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
