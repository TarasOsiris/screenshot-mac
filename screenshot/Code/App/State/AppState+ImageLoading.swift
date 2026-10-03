import ImageIO
import SwiftUI
import UniformTypeIdentifiers

extension AppState {
    /// How many decoded images to publish at a time. Every merge invalidates each canvas view
    /// that reads `screenshotImages`, so this is not per-image; it's small enough that a large
    /// project fills in visibly from the top instead of appearing all at once at the end.
    private static let imagePublishBatchSize = 4

    func loadScreenshotImages() {
        guard let activeId = activeProjectId else {
            projectOpen.finishImages()
            return
        }
        let resourcesURL = PersistenceService.resourcesDir(activeId)

        imageStore.cancelLoad()

        let toLoad = imageStore.retain(only: editorReferencedImageFileNames())
        guard !toLoad.isEmpty else {
            projectOpen.finishImages()
            return
        }
        projectOpen.beginImages(total: toLoad.count)
        imageStore.isLoading = true

        // Load downsampled images on a background thread, then publish in batches on main.
        // Full-resolution images are loaded from disk on-demand in export paths.
        let maxDim = ImageDownsampler.editorImageMaxDimension
        let batchSize = Self.imagePublishBatchSize
        imageStore.loadTask = Task.detached { [weak self] in
            var batch: [String: NSImage] = [:]
            var unloadable = UnloadableResources()
            var completed = 0

            for fileName in toLoad {
                if Task.isCancelled { return }
                let url = resourcesURL.appendingPathComponent(fileName)
                autoreleasepool {
                    if let image = ImageDownsampler.downsampledImage(at: url, maxDimension: maxDim)
                        ?? NSImage(contentsOf: url) {
                        batch[fileName] = image
                    } else {
                        unloadable.record(fileName, at: url)
                    }
                }
                completed += 1
                if batch.count >= batchSize || completed == toLoad.count {
                    let published = batch
                    batch = [:]
                    await self?.publishLoadedImages(published, completed: completed, for: activeId)
                }
            }
            guard !Task.isCancelled else { return }
            await self?.finishImageLoading(unloadable, in: resourcesURL, for: activeId)
        }
    }

    /// Both main-actor tails of the decode loop guard on the same thing: a switch may have landed
    /// while we were decoding, and the incoming project must not inherit these images.
    private func publishLoadedImages(_ images: [String: NSImage], completed: Int, for projectId: UUID) {
        guard activeProjectId == projectId else { return }
        imageStore.publish(images)
        projectOpen.advanceImages(to: completed)
    }

    private func finishImageLoading(_ unloadable: UnloadableResources, in resourcesURL: URL, for projectId: UUID) {
        guard activeProjectId == projectId else { return }
        imageStore.isLoading = false
        projectOpen.finishImages()
        if !unloadable.isEmpty {
            requestDownload(of: unloadable.missing.union(unloadable.pending), in: resourcesURL)
            imageStore.record(unloadable)
        }
        guard imageStore.needsReload else { return }
        imageStore.needsReload = false
        reloadUnresolvedScreenshotImages()
    }

    /// Re-reads what the last pass couldn't, once resources under the project change. Anything
    /// unresolved is absent from `screenshotImages`, so the ordinary load re-attempts exactly those
    /// names — and with nothing unresolved there is nothing to re-read, the common case.
    ///
    /// Missing counts as unresolved, not just pending: a peer's `project.json` is one small file
    /// and arrives before the file provider has placeholders for the resources it names, so those
    /// names stat as absent rather than not-downloaded. Gating the retry on `pending` alone left
    /// exactly the case this is for — a project opened mid-sync — stuck on the missing badge.
    func reloadUnresolvedScreenshotImages() {
        guard imageStore.hasUnresolved else { return }
        guard !imageStore.isLoading else {
            imageStore.needsReload = true
            return
        }
        loadScreenshotImages()
    }

    /// The container-wide prefetch pass is opportunistic, unordered and 24 URLs at a time, so the
    /// project actually on screen asks for its own resources by name. Absent names are asked for
    /// too: the file provider answers for an item it knows and errors harmlessly for one it
    /// doesn't, and we cannot tell those apart from here.
    private func requestDownload(of fileNames: Set<String>, in resourcesURL: URL) {
        guard !fileNames.isEmpty else { return }
        iCloudMonitor?.requestDownload(fileNames.map { resourcesURL.appendingPathComponent($0) })
    }
}
