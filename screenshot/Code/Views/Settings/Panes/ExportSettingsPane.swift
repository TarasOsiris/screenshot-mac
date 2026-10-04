import SwiftUI

#if os(macOS)
struct ExportSettingsPane: View {
    @AppStorage(AppSettingsKeys.exportFormat) private var exportFormat = AppSettingsKeys.Default.exportFormat
    @AppStorage(AppSettingsKeys.exportCustomSuffix) private var exportCustomSuffix = ""
    @AppStorage(AppSettingsKeys.exportNamingScheme) private var exportNamingScheme = ExportNamingScheme.standard
    @AppStorage(AppSettingsKeys.openExportFolderOnSuccess) private var openExportFolderOnSuccess = AppSettingsKeys.Default.openExportFolderOnSuccess
    /// Observation only — `ExportFolderBookmark` owns every read and write of the bookmark pair.
    @AppStorage(ExportFolderBookmark.pathKey) private var lastExportFolderPath = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("Export folder") {
                    HStack(spacing: 6) {
                        if !lastExportFolderPath.isEmpty {
                            pathPillView
                        } else {
                            Text("Ask each time")
                                .foregroundStyle(.tertiary)
                        }
                        Button("Choose…") {
                            guard let url = ExportFolderService.chooseFolder() else { return }
                            ExportFolderBookmark().save(url)
                        }
                    }
                }
            } footer: {
                Text("When set, Cmd+E exports directly to this folder without prompting.")
                    .foregroundStyle(.secondary)
            }

            ExportFormatPicker(selection: $exportFormat)

            Section {
                Picker("File layout", selection: $exportNamingScheme) {
                    ForEach(ExportNamingScheme.allCases) { Text($0.title).tag($0) }
                }
                TextField("Custom filename suffix", text: $exportCustomSuffix, prompt: Text("optional"))
            } footer: {
                ExportFileNameExample(scheme: exportNamingScheme, format: exportFormat, customSuffix: exportCustomSuffix)
                    .foregroundStyle(.secondary)
            }

            Toggle("Reveal in Finder after export", isOn: $openExportFolderOnSuccess)
        }
        .formStyle(.grouped)
    }

    private var pathPillView: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
                .font(.caption)
            Text(ExportFolderService.folderName(for: lastExportFolderPath))
                .lineLimit(1)
                .truncationMode(.middle)
            Button {
                ExportFolderBookmark().clear()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Clear export folder")
            .accessibilityLabel("Clear export folder")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary, in: .capsule)
        .help(lastExportFolderPath)
    }
}
#endif
