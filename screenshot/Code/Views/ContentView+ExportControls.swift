import SwiftUI

extension ContentView {
    var exportControlGroup: some View {
        ContentExportControl(
            isExporting: isExporting,
            exportSuccess: exportSuccess,
            buttonText: exportButtonText,
            helpText: exportHelpText,
            isDisabled: isExporting || state.rows.isEmpty,
            onExport: { exportScreenshots() }
        ) {
            exportMenuContent
        }
        .coachPopover(step: .export, state: state, arrowEdge: .top)
    }

    #if os(iOS)
    @ViewBuilder
    var iPadExportControl: some View {
        let isDisabled = isExporting || state.rows.isEmpty
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
        } label: {
            iPadExportLabel
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(isDisabled)
    }

    @ViewBuilder
    var iPadExportLabel: some View {
        if isExporting {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Exporting…")
            }
        } else {
            // square.and.arrow.up renders high (reserves space for the up-arrow); nudge the glyph down to align it.
            Label {
                Text(exportSuccess ? "Exported" : "Export")
            } icon: {
                Image(systemName: exportSuccess ? "checkmark.circle.fill" : "square.and.arrow.up")
                    .offset(y: exportSuccess ? 0 : -2)
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
        #endif
    }
}
