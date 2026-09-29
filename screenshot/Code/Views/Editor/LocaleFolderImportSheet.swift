import SwiftUI

/// A folder the user picked or dropped, planned against one row and waiting for confirmation.
struct LocaleFolderImportRequest: Identifiable {
    let id = UUID()
    let folder: URL
    let rowId: UUID
    let rowSize: CGSize
    let plan: LocaleFolderImportPlan
    /// Languages added in the sheet have no screenshots yet, so toggling them can't change this.
    let replacedCount: Int
}

struct LocaleFolderImportSheet: View {
    let request: LocaleFolderImportRequest
    let localeLabel: (String) -> String
    let projectLocaleCodes: [String]
    let onImport: ([LocaleDefinition]) -> Void
    let onCancel: () -> Void

    @State private var localesToAdd: Set<String> = []

    /// One entry per language: `fr-FR` and `fr-CA` can both resolve to one preset, and adding it
    /// twice would plan — and import — its screenshots twice.
    private var addableLocales: [(folders: [String], locale: LocaleDefinition)] {
        var order: [String] = []
        var byCode: [String: (folders: [String], locale: LocaleDefinition)] = [:]
        for folder in request.plan.unmatchedLocaleFolders {
            guard let locale = LocaleFolderImportPlanner.presetLocale(forFolderName: folder),
                  !projectLocaleCodes.contains(locale.code) else { continue }
            if byCode[locale.code] == nil {
                order.append(locale.code)
                byCode[locale.code] = ([folder], locale)
            } else {
                byCode[locale.code]?.folders.append(folder)
            }
        }
        return order.compactMap { byCode[$0] }
    }

    var body: some View {
        let addableLocales = self.addableLocales
        VStack(alignment: .leading, spacing: 14) {
            Text("Import Localized Screenshots")
                .font(.headline)
            Text(request.folder.lastPathComponent)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if request.plan.batches.isEmpty {
                Group {
                    if addableLocales.isEmpty {
                        Text("No screenshots in this folder match this row's languages and its \(sizeLabel) size. Name subfolders by language — for example en-US and de-DE — or add the language code to each file name.")
                    } else {
                        Text("None of this folder's languages are in the project yet. Turn on the ones to add below, and their screenshots import with them.")
                    }
                }
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
                    ForEach(addableLocales, id: \.locale.code) { entry in
                        Toggle(isOn: addBinding(entry.locale.code)) {
                            Text("Add \(entry.locale.flagLabel) (\(entry.folders.joined(separator: ", ")))")
                        }
                    }
                }
            }

            let addable = Set(addableLocales.flatMap(\.folders))
            let ignored = request.plan.unmatchedLocaleFolders.filter { !addable.contains($0) }
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

            if request.replacedCount > 0 {
                Label(
                    "Replaces ^[\(request.replacedCount) screenshot](inflect: true) already in this row.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
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
