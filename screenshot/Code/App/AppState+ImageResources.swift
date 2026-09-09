import ImageIO
import os
import SwiftUI

extension AppState {
    // MARK: - Image Helpers

    /// Collects all image filenames (base + locale overrides) for a set of shapes.
    func imageFileNames(for shapes: [CanvasShapeModel]) -> [String] {
        shapes.flatMap { $0.allImageFileNames } + shapes.flatMap { localeOverrideImageFileNames(for: $0.id) }
    }

    // MARK: - Image Cleanup

    /// The extensions the app itself writes as image resources.
    nonisolated static let imageResourceExtensions: Set<String> = ["png"]

    /// Above this, one pass has removed more than any plausible manual deletion, and the sweep
    /// itself is the suspect. Below it, the breadcrumb is enough.
    private nonisolated static let largeSweepThreshold = 50

    /// Image files in `files` that aren't referenced by the model.
    ///
    /// An allowlist, not a "not a font" denylist: `resources/` also holds entries we did not put
    /// there and cannot classify, and one of them is fatal to touch. A ubiquitous resource whose
    /// bytes haven't arrived exists on disk only as the hidden sibling `.<name>.png.icloud`, whose
    /// name is not the referenced name and whose extension is not a font — so the old filter called
    /// it an orphan and deleted it, which deletes the item itself on every device. That is how a
    /// project opened before its screenshots finished syncing lost all 266 of them.
    nonisolated static func orphanedResourceURLs(in files: [URL], referenced: Set<String>) -> [URL] {
        files.filter { url in
            let fileName = url.lastPathComponent
            guard !fileName.hasPrefix("."),
                  imageResourceExtensions.contains(url.pathExtension.lowercased()) else { return false }
            return !referenced.contains(fileName)
        }
    }

    /// Scans the resources directory and deletes orphans off-main so a project switch doesn't
    /// block the push animation. The `referenced` set is re-read on the main actor at deletion
    /// time (not snapshotted at call time) so an image imported right after the open isn't
    /// mistaken for an orphan, and the task bails if the active project changed. Skips the
    /// in-memory `screenshotImages` eviction (it uses `removeItem`, not `removeImageFile`); on
    /// open that dict was just cleared and is repopulated by `loadScreenshotImages`.
    ///
    /// Only ever called for a project the user just opened. A document replaced by an iCloud
    /// reload must not reach here: a peer's `project.json` can be newer by mtime and behind in
    /// content, and sweeping against it deletes resources this device just wrote.
    func cleanupOrphanedResourceFilesAsync(for projectId: UUID) {
        forgetDeferredOrphans()
        let resourcesURL = PersistenceService.resourcesDir(projectId)
        Task.detached(priority: .utility) { [weak self] in
            guard let files = try? FileManager.default.contentsOfDirectory(at: resourcesURL, includingPropertiesForKeys: nil) else { return }
            // Read the live referenced set after listing the directory, so files created
            // after the listing are never deletion candidates and the set reflects the
            // current model. Bail if the project changed under us.
            let referenced: Set<String>? = await MainActor.run {
                guard let self, self.activeProjectId == projectId else { return nil }
                return self.allReferencedImageFileNames()
            }
            guard let referenced else { return }
            let orphans = AppState.orphanedResourceURLs(in: files, referenced: referenced)
            for fileURL in orphans {
                try? FileManager.default.removeItem(at: fileURL)
            }
            AppState.reportSweep(listed: files.count, referenced: referenced.count, removed: orphans.count)
        }
    }

    /// Counts only — a file name here would name what the user is building.
    private nonisolated static func reportSweep(listed: Int, referenced: Int, removed: Int) {
        guard removed > 0 else { return }
        let extra: [String: Any] = ["listed": listed, "referenced": referenced, "removed": removed]
        CrashReportingService.breadcrumb(.persistence, "Swept orphaned resources", data: extra)
        guard removed >= largeSweepThreshold else { return }
        CrashReportingService.report(.orphanSweepRemovedManyResources, extra: extra, level: .warning)
    }

    /// The document was replaced, so the parked orphans were measured against an undo stack that
    /// no longer exists. Anything genuinely dead is picked up by the next open's directory scan.
    func forgetDeferredOrphans() {
        deferredOrphanedImages.removeAll()
    }

    /// The generation past which an undo step has been pushed off the end of the stack, so
    /// nothing on it can restore a reference recorded at or before it. nil with no UndoManager.
    /// These cleanups run *inside* the mutation, so a file parked at generation P is restored by
    /// the step pushed at P+1, which survives until `depth` further pushes evict it.
    private var undoReachHorizon: Int? {
        guard let undoManager else { return nil }
        // An injected manager may report unlimited (0); never reaping at all is what leaked.
        let depth = undoManager.levelsOfUndo > 0 ? undoManager.levelsOfUndo : AppState.undoDepth
        return undoStepGeneration - depth - 1
    }

    func cleanupUnreferencedImage(_ fileName: String?) {
        guard let fileName, !isImageFileReferenced(fileName) else { return }
        retireImageFile(fileName)
    }

    /// Batch cleanup: collects all referenced filenames once, then retires any candidate that is unreferenced.
    func cleanupUnreferencedImages(_ fileNames: [String?]) {
        let candidates = Set(fileNames.compactMap { $0 })
        guard !candidates.isEmpty else { return }
        let referenced = allReferencedImageFileNames()
        for fileName in candidates where !referenced.contains(fileName) {
            retireImageFile(fileName)
        }
    }

    /// Deleting on the spot would break undo: a registered step restores the model's reference
    /// (and these cleanups run inside undoable mutations), but nothing re-creates the file — ⌘Z
    /// would bring the shape back empty. So while an UndoManager exists the orphan is parked
    /// and swept once it falls off the end of the undo stack, rather than surviving the whole
    /// session waiting for a project switch.
    private func retireImageFile(_ fileName: String) {
        guard undoManager != nil else {
            removeImageFile(fileName)
            return
        }
        deferredOrphanedImages[fileName] = undoStepGeneration
    }

    /// Deletes parked orphans no undo step can reach any more, and forgets any whose reference
    /// came back (an undo restored it). Runs on the debounced save tick.
    func sweepUnreachableOrphanedImages() {
        guard !deferredOrphanedImages.isEmpty else { return }
        let referenced = allReferencedImageFileNames()
        for (fileName, generation) in deferredOrphanedImages {
            if referenced.contains(fileName) {
                deferredOrphanedImages[fileName] = nil
            } else if let horizon = undoReachHorizon, generation > horizon {
                continue
            } else {
                removeImageFile(fileName)
                deferredOrphanedImages[fileName] = nil
            }
        }
    }

    private func removeImageFile(_ fileName: String) {
        screenshotImages.removeValue(forKey: fileName)
        if let projectId = activeProjectId {
            let fileURL = PersistenceService.resourcesDir(projectId).appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// A failed copy leaves the duplicated shape pointing at a file that was never written, so
    /// it renders as a hole rather than an error.
    private func copyImageResource(from src: URL, to dst: URL, kind: String) {
        do {
            try FileManager.default.copyItem(at: src, to: dst)
        } catch {
            CrashReportingService.report(.imageResourceCopyFailed, error: error, extra: ["kind": kind])
        }
    }

    /// Copy image files for a duplicated shape so it has its own independent files.
    /// Updates the shape's image references in-place and copies locale override image files.
    func copyImageFiles(for newShape: inout CanvasShapeModel, originalId: UUID) {
        guard let activeId = activeProjectId else { return }
        let resourcesURL = PersistenceService.resourcesDir(activeId)
        let fm = FileManager.default

        // Copy base image file (imageFileName or screenshotFileName)
        if let originalFile = newShape.displayImageFileName {
            let srcURL = resourcesURL.appendingPathComponent(originalFile)
            let newFile = "\(newShape.id.uuidString).png"
            let dstURL = resourcesURL.appendingPathComponent(newFile)
            if fm.fileExists(atPath: srcURL.path) {
                copyImageResource(from: srcURL, to: dstURL, kind: "display")
                newShape.displayImageFileName = newFile
                screenshotImages[newFile] = screenshotImages[originalFile]
            }
        }

        if let originalFillFile = newShape.fillImageConfig?.fileName {
            let srcURL = resourcesURL.appendingPathComponent(originalFillFile)
            let newFillFile = "fill-\(newShape.id.uuidString).png"
            let dstURL = resourcesURL.appendingPathComponent(newFillFile)
            if fm.fileExists(atPath: srcURL.path) {
                copyImageResource(from: srcURL, to: dstURL, kind: "fill")
                newShape.fillImageConfig?.fileName = newFillFile
                screenshotImages[newFillFile] = screenshotImages[originalFillFile]
            }
        }

        let originalKey = originalId.uuidString
        let newKey = newShape.id.uuidString
        for localeCode in localeState.overrides.keys {
            guard var override = localeState.overrides[localeCode]?[originalKey],
                  let originalFile = override.overrideImageFileName else { continue }
            let srcURL = resourcesURL.appendingPathComponent(originalFile)
            let newFile = "\(newShape.id.uuidString)-\(localeCode).png"
            let dstURL = resourcesURL.appendingPathComponent(newFile)
            if fm.fileExists(atPath: srcURL.path) {
                copyImageResource(from: srcURL, to: dstURL, kind: "localeOverride")
                override.overrideImageFileName = newFile
                localeState.overrides[localeCode]?[newKey] = override
                screenshotImages[newFile] = screenshotImages[originalFile]
            }
        }
    }

    /// Collect all screenshot filenames from locale overrides for a shape.
    func localeOverrideImageFileNames(for shapeId: UUID) -> [String] {
        let key = shapeId.uuidString
        return localeState.overrides.values.compactMap { $0[key]?.overrideImageFileName }
    }

    func isImageFileReferenced(_ fileName: String) -> Bool {
        let referencedInRows = rows.contains { row in
            row.backgroundImageConfig.fileName == fileName ||
            row.templates.contains { $0.backgroundImageConfig.fileName == fileName } ||
            row.shapes.contains { shape in
                shape.allImageFileNames.contains(fileName)
            }
        }
        if referencedInRows { return true }

        return localeState.overrides.values.contains { shapeOverrides in
            shapeOverrides.values.contains { $0.overrideImageFileName == fileName }
        }
    }

    /// Loads full-resolution images for the given filenames from the *active* project's
    /// resources. The loader itself is project-agnostic — see `ImageResourceLoader`.
    /// Pass `cache` to avoid redundant disk reads across multiple calls (e.g. during export).
    func loadFullResolutionImages(
        fileNames: Set<String>,
        cache: inout [String: NSImage]
    ) -> [String: NSImage] {
        guard let activeId = activeProjectId else { return [:] }
        return ImageResourceLoader.loadFullResolution(
            fileNames: fileNames,
            from: PersistenceService.resourcesDir(activeId),
            cache: &cache
        )
    }

    // MARK: - Referenced Image Filenames

    /// The document view of the open project. The walks themselves live on `ProjectDocument` so a
    /// project the editor does not have open answers them identically.
    var document: ProjectDocument {
        ProjectDocument(rows: rows, localeState: localeState)
    }

    /// Image filenames needed for the editor (base shapes + active locale overrides only),
    /// in document order.
    func editorReferencedImageFileNames() -> [String] {
        document.editorReferencedImageFileNames()
    }

    /// Collect all referenced image filenames in a single pass (for batch cleanup).
    func allReferencedImageFileNames() -> Set<String> {
        document.allReferencedImageFileNames()
    }

    func referencedImageFileNames(forRow row: ScreenshotRow, localeCode: String) -> Set<String> {
        document.referencedImageFileNames(forRow: row, localeCode: localeCode)
    }

    /// Loads full-resolution images for a single row and locale from disk.
    func loadFullResolutionImages(forRow row: ScreenshotRow, localeCode: String) -> [String: NSImage] {
        let fileNames = referencedImageFileNames(forRow: row, localeCode: localeCode)
        var cache: [String: NSImage] = [:]
        return loadFullResolutionImages(fileNames: fileNames, cache: &cache)
    }
}
