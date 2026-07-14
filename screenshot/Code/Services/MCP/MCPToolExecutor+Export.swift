#if DEBUG && os(macOS)
import Foundation
import MCP

extension MCPToolExecutor {

    struct ExportResult: Encodable {
        let folder: String
        let files: [String]
    }

    func exportProject(_ args: MCPArguments) async throws -> CallTool.Result {
        guard let project = state.activeProject else {
            throw MCPToolError.failed("No active project")
        }
        guard !state.rows.isEmpty else {
            throw MCPToolError.failed("Project has no rows to export")
        }

        let format: ExportImageFormat = switch args.string("format") {
        case nil, "png": .png
        case "jpeg", "jpg": .jpeg
        case let other?: throw MCPToolError.invalidArgument("format", "expected png or jpeg, got \(other)")
        }

        if let locale = args.string("locale"),
           !state.localeState.locales.contains(where: { $0.code == locale }) {
            throw MCPToolError.notFound("Locale \(locale)")
        }

        let destination: URL
        if let folderPath = args.string("folder_path") {
            destination = URL(fileURLWithPath: (folderPath as NSString).expandingTildeInPath, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            } catch {
                throw MCPToolError.failed("Cannot write to \(destination.path) (sandbox) — omit folder_path to export to a temp folder and copy the files from there")
            }
        } else {
            destination = try ExportService.makeTempExportFolder()
        }

        let state = self.state
        do {
            let result = try await ExportService.exportAll(
                rows: state.rows,
                projectName: project.name,
                to: destination,
                format: format,
                imageProvider: { row, localeCode in
                    state.loadFullResolutionImages(forRow: row, localeCode: localeCode)
                },
                localeState: state.localeState,
                localeFilter: args.string("locale"),
                availableFontFamilies: state.availableFontFamilySet
            )
            return try MCPResultEncoding.result(ExportResult(
                folder: result.folderURL.path,
                files: result.fileURLs.map(\.path).sorted()
            ))
        } catch {
            throw MCPToolError.failed("Export failed: \(error.localizedDescription)")
        }
    }
}
#endif
