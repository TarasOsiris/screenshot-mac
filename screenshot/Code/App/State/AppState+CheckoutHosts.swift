import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

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

    func mutate<R>(_ actionName: String, _ body: (inout ProjectDocument) throws -> R) rethrows -> R {
        try state.withDocument(actionName, body)
    }

    /// `withDocument` already scheduled the debounced save.
    func commit() throws {}

    func commitPendingEdits() { state.commitAllPendingEdits() }

    func copyImageResource(_ fileName: String, to newFileName: String) -> Bool {
        state.copyImageResource(fileName, to: newFileName)
    }

    func publishThumbnail(_ thumbnail: NSImage, named fileName: String) {
        state.screenshotImages[fileName] = thumbnail
    }

    func didRepointImages() { state.loadScreenshotImages() }
}

/// The editor does not have this project open, so the checkout owns it outright.
@MainActor
final class DetachedProjectHost: ProjectMutationHost {
    private let projectId: UUID
    private let state: AppState
    private(set) var document: ProjectDocument
    private(set) var modifiedAt: Date?
    private var isDirty = false
    /// Files the edits stopped referencing. With no undo stack to bring them back, they go once the write lands.
    private var freedImageFiles: Set<String> = []
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

    func mutate<R>(_ actionName: String, _ body: (inout ProjectDocument) throws -> R) rethrows -> R {
        var updated = document
        let result = try body(&updated)
        if updated != document {
            let referenced = updated.allReferencedImageFileNames()
            freedImageFiles.formUnion(document.allReferencedImageFileNames().subtracting(referenced))
            freedImageFiles.subtract(referenced)
            document = updated
            isDirty = true
        }
        return result
    }

    func commitPendingEdits() {}

    func copyImageResource(_ fileName: String, to newFileName: String) -> Bool {
        PersistenceService.copyImageResource(fileName, to: newFileName, inProject: projectId)
    }

    func publishThumbnail(_ thumbnail: NSImage, named fileName: String) {}

    func didRepointImages() {}

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
        state.recordProjectModified(projectId, at: data.modifiedAt)

        let monitor = state.iCloudMonitor
        let freed = freedImageFiles.map { PersistenceService.resourcesDir(projectId).appendingPathComponent($0) }
        // The shared save queue, not a private one: `readProjectAfterQueuedWrites` puts its
        // barrier here too, so an open enqueued after this write reads these bytes.
        state.enqueueProjectWrite(projectId, data: data) {
            monitor?.snapshotAfterWrite()
            // Only once the file stops naming them: a failed write leaves the old document on disk.
            freed.forEach(AppState.removeUnreferencedImageResource)
        }
        state.saveIndexAsync()
        isDirty = false
        freedImageFiles = []
    }
}
