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
protocol ProjectMutationHost: AnyObject {
    var document: ProjectDocument { get }
    var modifiedAt: Date? { get }
    var availableFontFamilySet: Set<String> { get }
    func mutate(_ actionName: String, _ body: (inout ProjectDocument) -> Void)
    func commit() throws
    /// Lands the user's in-progress typing or composing drag before a read. Only the open document
    /// has any; a detached one is already whatever the file says.
    func commitPendingEdits()
}

/// The editor already has this project open, so it is the authoritative in-memory copy.
///
/// Writing around it would discard the user's unsaved edits — their composing drag and undebounced
/// typing live only in memory — and adopting a file afterwards would call
/// `undoManager?.removeAllActions()`, wiping their undo stack on every agent edit.
@MainActor
final class OpenProjectHost: ProjectMutationHost {
    private let state: AppState

    init(state: AppState) { self.state = state }

    var document: ProjectDocument { state.document }
    var modifiedAt: Date? { state.documentStamp?.modifiedAt }
    var availableFontFamilySet: Set<String> { state.availableFontFamilySet }

    func mutate(_ actionName: String, _ body: (inout ProjectDocument) -> Void) {
        state.withDocument(actionName, body)
    }

    /// `withDocument` already scheduled the debounced save.
    func commit() throws {}

    func commitPendingEdits() { state.commitAllPendingEdits() }
}

/// The editor does not have this project open, so the checkout owns it outright.
@MainActor
final class DetachedProjectHost: ProjectMutationHost {
    private let projectId: UUID
    private let state: AppState
    private(set) var document: ProjectDocument
    private(set) var modifiedAt: Date?
    private var isDirty = false
    private let fontScope: ProjectFontScope

    init(projectId: UUID, state: AppState, data: ProjectData, fontScope: ProjectFontScope) {
        self.projectId = projectId
        self.state = state
        self.document = ProjectDocument(data)
        self.modifiedAt = data.modifiedAt
        self.fontScope = fontScope
    }

    /// Non-optional: a detached host that could not resolve its own fonts is refused at `open`
    /// rather than silently rendering with whichever project the editor happens to have open.
    var availableFontFamilySet: Set<String> { fontScope.availableFamilySet }

    func mutate(_ actionName: String, _ body: (inout ProjectDocument) -> Void) {
        body(&document)
        isDirty = true
    }

    func commitPendingEdits() {}

    func commit() throws {
        guard isDirty else { return }
        // Re-checked with no `await` since the gate was taken: if the user opened this project
        // under us, that copy is now authoritative and writing the file would lose their edits.
        if state.activeProjectId == projectId {
            // Our snapshot predates the awaits, so writing it over their document — in memory or on
            // disk — discards whatever they did in that window. There is no merge available here:
            // the caller has to redo the edit against the now-open project.
            throw ProjectCheckoutError.openedConcurrently(name: state.activeProject?.name ?? "")
        }

        // `ProjectData.name` is the only copy an index rebuild can recover from, so a write that
        // drops it silently loses the project's name.
        let name = state.projects.first { $0.id == projectId }?.name
        let data = document.projectData(name: name)
        modifiedAt = data.modifiedAt

        // Without the mtime stamp the project card sorts stale and `diskCachedImage` keeps
        // serving the pre-edit thumbnail forever.
        if let index = state.projects.firstIndex(where: { $0.id == projectId }) {
            state.projects[index].modifiedAt = data.modifiedAt
        }
        // Without this the monitor reads our own write as a remote change and reloads the *open*
        // project, costing the user their undo stack over an edit to a different project.
        state.iCloudMonitor?.recordOwnWrite([
            PersistenceService.projectDataURL(projectId),
            PersistenceService.translationCatalogURL(projectId),
        ])

        let monitor = state.iCloudMonitor
        let id = projectId
        let owner = state
        // The shared save queue, not a private one: `loadProjectAfterQueuedWrites` puts its
        // barrier here too, so an open enqueued after this write reads these bytes.
        AppState.saveQueue.async {
            do {
                try PersistenceService.saveProject(id, data: data)
                monitor?.snapshotAfterWrite()
            } catch {
                // Through the shared reporter, so a failed detached write raises `saveError` like
                // every other save path instead of reaching Sentry and nobody else.
                Task { @MainActor in owner.reportProjectSaveFailure(error) }
            }
        }
        state.saveIndexAsync()
        isDirty = false
    }
}

/// A project checked out for editing, whether or not the editor has it open.
///
/// Every MCP tool operates on one of these, and nothing in it consults `activeProjectId` to decide
/// *what* to act on — only to decide who commits. The tool contract is therefore identical either
/// way: same arguments, same result, same resulting document.
@MainActor
final class ProjectCheckout: RowRenderSource {
    let projectId: UUID
    let projectName: String
    let ascAppId: String?
    private let host: ProjectMutationHost
    private let resourcesURL: URL
    private let fontScope: ProjectFontScope?

    private init(
        projectId: UUID,
        projectName: String,
        ascAppId: String?,
        host: ProjectMutationHost,
        fontScope: ProjectFontScope?
    ) {
        self.projectId = projectId
        self.projectName = projectName
        self.ascAppId = ascAppId
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

    func loadFullResolutionImages(fileNames: Set<String>, cache: inout [String: NSImage]) -> [String: NSImage] {
        ImageResourceLoader.loadFullResolution(fileNames: fileNames, from: resourcesURL, cache: &cache)
    }

    func withResolvedFonts<R>(_ body: () -> R) -> R {
        fontScope.map { $0.withResolvedFonts(body) } ?? body()
    }

    // MARK: - Editing

    func mutate(_ actionName: String, _ body: (inout ProjectDocument) -> Void) {
        host.mutate(actionName, body)
    }

    func commit() throws { try host.commit() }

    /// Call before rendering: the open document's undebounced typing lives only in memory.
    func commitPendingEdits() { host.commitPendingEdits() }

    func dispose() { fontScope?.dispose() }

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
                host: OpenProjectHost(state: state),
                fontScope: nil
            )
        }

        // Drains the save-queue barrier first, so a write for a project the user just switched
        // away from has landed before we read it.
        guard let data = await AppState.loadProjectAfterQueuedWrites(projectId) else {
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
            host: DetachedProjectHost(projectId: projectId, state: state, data: data, fontScope: fontScope),
            fontScope: fontScope
        )
    }
}
