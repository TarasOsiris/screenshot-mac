import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Why a checkout could not be opened. Its own type rather than the MCP tool error, which is
/// `#if os(macOS)` — this file is not, and must not become so.
enum ProjectCheckoutError: Error, LocalizedError {
    case notFound(UUID)
    case unreadable(name: String)
    case fontsUnavailable(name: String)
    case openedConcurrently(name: String)

    var errorDescription: String? {
        switch self {
        case .notFound(let id):
            String(localized: "Project \(id.uuidString) not found")
        case .unreadable(let name):
            String(localized: "Project \(name) could not be read from disk")
        case .fontsUnavailable(let name):
            String(localized: "\(name) uses fonts whose files have not downloaded yet.")
        case .openedConcurrently(let name):
            String(localized: "\(name) was opened in the app while this edit was in progress. Retry it.")
        }
    }
}

/// Where a project's edits are committed. Two implementations, chosen per call by whoever already
/// holds the project — never two blind writers for one project.
@MainActor
protocol ProjectMutationHost: AnyObject, ImageResourceCopying {
    var document: ProjectDocument { get }
    var modifiedAt: Date? { get }
    var availableFontFamilySet: Set<String> { get }
    /// Applies `body` as one edit. A throw leaves the document untouched.
    func mutate<R>(_ actionName: String, _ body: (inout ProjectDocument) throws -> R) rethrows -> R
    func commit() throws
    /// Lands the user's in-progress typing or composing drag before a read. Only the open document
    /// has any; a detached one is already whatever the file says.
    func commitPendingEdits()
    /// Hands the editor a freshly written image. Only the open document has an editor to show it.
    func publishThumbnail(_ thumbnail: NSImage, named fileName: String)
    /// The document now points at images the editor never decoded (a new base language's screenshots).
    func didRepointImages()
}

/// A project checked out for editing, whether or not the editor has it open.
///
/// Every MCP tool operates on one of these, and nothing in it consults `activeProjectId` to decide
/// *what* to act on — only to decide who commits. The tool contract is therefore identical either
/// way: same arguments, same result, same resulting document.
@MainActor
final class ProjectCheckout: RowRenderSource, ImageResourceCopying {
    let projectId: UUID
    let projectName: String
    let ascAppId: String?
    let googlePlayPackageName: String?
    private let host: ProjectMutationHost
    private let resourcesURL: URL
    private let fontScope: ProjectFontScope?

    private init(
        projectId: UUID,
        projectName: String,
        ascAppId: String?,
        googlePlayPackageName: String?,
        host: ProjectMutationHost,
        fontScope: ProjectFontScope?
    ) {
        self.projectId = projectId
        self.projectName = projectName
        self.ascAppId = ascAppId
        self.googlePlayPackageName = googlePlayPackageName
        self.host = host
        self.resourcesURL = PersistenceService.resourcesDir(projectId)
        self.fontScope = fontScope
    }

    var document: ProjectDocument { host.document }
    var rows: [ScreenshotRow] { document.rows }
    var documentStamp: DocumentStamp { DocumentStamp(projectId: projectId, modifiedAt: host.modifiedAt) }

    // MARK: - RowRenderSource

    var localeState: LocaleState { document.localeState }
    var availableFontFamilySet: Set<String> { host.availableFontFamilySet }

    func referencedImageFileNames(forRow row: ScreenshotRow, localeCode: String) -> Set<String> {
        document.referencedImageFileNames(forRow: row, localeCode: localeCode)
    }

    func loadFullResolutionImages(fileNames: Set<String>) async -> [String: NSImage] {
        await ImageResourceLoader.loadFullResolution(fileNames: fileNames, from: resourcesURL)
    }

    func withResolvedFonts<R>(_ body: () -> R) -> R {
        fontScope.map { $0.withResolvedFonts(body) } ?? body()
    }

    // MARK: - Editing

    /// A closed project's checkout is a snapshot: callers must serialize edits to it (`MCPToolExecutor.serializingEdits`).
    func mutate<R>(_ actionName: String, _ body: (inout ProjectDocument) throws -> R) rethrows -> R {
        try host.mutate(actionName, body)
    }

    func commit() throws { try host.commit() }

    func copyImageResource(_ fileName: String, to newFileName: String) -> Bool {
        host.copyImageResource(fileName, to: newFileName)
    }

    /// Call before rendering: the open document's undebounced typing lives only in memory.
    func commitPendingEdits() { host.commitPendingEdits() }

    func didRepointImages() { host.didRepointImages() }

    func dispose() { fontScope?.dispose() }

    // MARK: - Image resources

    /// Writes staged images into this project's resources folder. The open project also gets each
    /// editor thumbnail, so the canvas shows it without a reload. Returns one message per failed write.
    func flush(_ staged: [StagedImageWrite]) async -> [String] {
        await DocumentEditing.flush(staged, to: resourcesURL) { [host] fileName, thumbnail in
            host.publishThumbnail(thumbnail, named: fileName)
        }
    }

    // MARK: - Opening

    /// Opens `projectId` for editing. The editor's open project decides only who commits.
    static func open(projectId: UUID, state: AppState) async throws -> ProjectCheckout {
        guard let project = state.visibleProjects.first(where: { $0.id == projectId }) else {
            throw ProjectCheckoutError.notFound(projectId)
        }
        // A switch in flight has `activeProjectId` already pointing at the incoming project while
        // `rows` still belong to the outgoing one.
        await state.projectOpenTask?.value

        if state.activeProjectId == projectId {
            // The open document's fonts are already registered process-wide by `CustomFontLibrary`.
            return ProjectCheckout(
                projectId: projectId,
                projectName: project.name,
                ascAppId: project.ascAppId,
                googlePlayPackageName: project.googlePlayPackageName,
                host: OpenProjectHost(state: state),
                fontScope: nil
            )
        }

        // Drains the save-queue barrier first, so a write for a project the user just switched
        // away from has landed before we read it.
        guard let data = await AppState.readProjectAfterQueuedWrites(projectId)?.data else {
            throw ProjectCheckoutError.unreadable(name: project.name)
        }
        // Without the project's own fonts registered, its custom-font text renders in the system
        // face — silently, and identically to a correct render at every other layer. A nil scope
        // means a font file exists but its bytes have not downloaded, which is a refusal, not a
        // reason to fall back to somebody else's fonts.
        guard let fontScope = await ProjectFontScope.make(projectId: projectId) else {
            throw ProjectCheckoutError.fontsUnavailable(name: project.name)
        }
        return ProjectCheckout(
            projectId: projectId,
            projectName: project.name,
            ascAppId: project.ascAppId,
            googlePlayPackageName: project.googlePlayPackageName,
            host: DetachedProjectHost(projectId: projectId, state: state, data: data, fontScope: fontScope),
            fontScope: fontScope
        )
    }
}
