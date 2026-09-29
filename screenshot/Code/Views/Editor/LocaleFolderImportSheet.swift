import SwiftUI

/// A folder the user picked or dropped, planned against one row and waiting for confirmation.
struct LocaleFolderImportRequest: Identifiable {
    let id = UUID()
    let folder: URL
    let rowId: UUID
    let rowSize: CGSize
    let plan: LocaleFolderImportPlan
}

struct LocaleFolderImportSheet: View {
    let request: LocaleFolderImportRequest
    let localeLabel: (String) -> String
    let onImport: ([LocaleDefinition]) -> Void
    let onCancel: () -> Void

    @State private var localesToAdd: Set<String> = []

    private var addableLocales: [(folder: String, locale: LocaleDefinition)] {
        request.plan.unmatchedLocaleFolders.compactMap { folder in
            LocaleFolderImportPlanner.presetLocale(forFolderName: folder).map { (folder, $0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import Localized Screenshots")
                .font(.headline)
            Text(request.folder.lastPathComponent)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if request.plan.batches.isEmpty {
                Text("No screenshots in this folder match this row's languages and its \(sizeLabel) size. Name subfolders by language — for example en-US and de-DE — or add the language code to each file name.")
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(request.plan.batches, id: \.localeCode) { batch in
                        LabeledContent(localeLabel(batch.localeCode)) {
                            Text("^[\(batch.files.count) screenshot](inflect: true)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !addableLocales.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Languages not in this project")
                        .font(.subheadline.weight(.semibold))
                    ForEach(addableLocales, id: \.folder) { entry in
                        Toggle(isOn: addBinding(entry.locale.code)) {
                            Text("Add \(entry.locale.flagLabel) (\(entry.folder))")
                        }
                    }
                }
            }

            let ignored = request.plan.unmatchedLocaleFolders.filter { LocaleFolderImportPlanner.presetLocale(forFolderName: $0) == nil }
            if !ignored.isEmpty {
                Label("Skipped folders: \(ignored.joined(separator: ", "))", systemImage: "questionmark.folder")
                    .foregroundStyle(.secondary)
            }
            if !request.plan.skippedForSize.isEmpty {
                Label(
                    "^[\(request.plan.skippedForSize.count) image](inflect: true) skipped: not \(sizeLabel).",
                    systemImage: "aspectratio"
                )
                .foregroundStyle(.secondary)
                .help(request.plan.skippedForSize.map(\.lastPathComponent).joined(separator: "\n"))
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Import") {
                    onImport(addableLocales.map(\.locale).filter { localesToAdd.contains($0.code) })
                }
                .keyboardShortcut(.defaultAction)
                .disabled(request.plan.batches.isEmpty && localesToAdd.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var sizeLabel: String {
        "\(Int(request.rowSize.width))×\(Int(request.rowSize.height))"
    }

    private func addBinding(_ code: String) -> Binding<Bool> {
        Binding(
            get: { localesToAdd.contains(code) },
            set: { isOn in
                if isOn { localesToAdd.insert(code) } else { localesToAdd.remove(code) }
            }
        )
    }
}
