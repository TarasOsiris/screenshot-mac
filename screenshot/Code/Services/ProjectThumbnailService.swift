import SwiftUI

/// Bounds how many thumbnails build concurrently. Without this, scrolling a grid of N cards
/// fans out N detached IO tasks — each potentially blocking on an undownloaded iCloud file —
/// plus N main-actor renders, which is exactly the freeze we're avoiding.
actor ThumbnailConcurrencyGate {
    static let shared = ThumbnailConcurrencyGate(limit: 3)

    private let limit: Int
    private var active = 0
    private var peak = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    /// Highest number of permits held simultaneously — for tests.
    var peakActive: Int { peak }

    func acquire() async {
        if active < limit {
            active += 1
            peak = max(peak, active)
            return
        }
        await withCheckedContinuation { waiters.append($0) }
        // Resumed by `release()`, which transfers its slot to us — `active` is unchanged.
    }

    func release() {
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
        } else {
            active -= 1
        }
    }
}

/// Renders a small snapshot of a project's first row for use as a card thumbnail.
/// Loads the project's data straight from disk (the project need not be active), renders
/// through the shared export path so the thumbnail matches the editor, at card scale.
///
/// Blocking IO (project + image reads, which on iCloud can stall on an undownloaded file)
/// runs off the main thread; only the SwiftUI render stays on the main actor (ImageRenderer
/// requirement). Results are cached in memory per project + `modifiedAt`, and persisted as a
/// PNG under `PersistenceService.thumbnailsDir` so cold launches don't re-render everything.
@MainActor
enum ProjectThumbnailService {
    private struct Key: Hashable {
        let id: UUID
        let modifiedAt: Date
    }

    private struct RenderInputs {
        let row: ScreenshotRow
        let images: [String: NSImage]
        let localeCode: String
        let localeState: LocaleState
    }

    private static let targetDisplaySize = CGSize(width: 900, height: 675)
    private static var cache: [Key: Image] = [:]

    static func thumbnail(for project: Project) async -> Image? {
        let key = Key(id: project.id, modifiedAt: project.modifiedAt)
        if let cached = cache[key] { return cached }

        // Disk cache: a previously-rendered PNG that's at least as new as the project.
        if let nsImage = await Task.detached(priority: .utility, operation: { diskCachedImage(for: project) }).value {
            if Task.isCancelled { return nil }
            return store(Image(nsImage: nsImage), for: key)
        }

        await ThumbnailConcurrencyGate.shared.acquire()
        defer { Task { await ThumbnailConcurrencyGate.shared.release() } }

        if Task.isCancelled { return nil }

        // Off-main: blocking reads (coordinated reads of possibly-undownloaded iCloud files).
        let inputs = await Task.detached(priority: .utility) { () -> RenderInputs? in
            loadRenderInputs(for: project.id)
        }.value

        guard let inputs, !Task.isCancelled else { return nil }

        // Main: SwiftUI render (ImageRenderer must run on the main actor).
        let displayScale = thumbnailDisplayScale(for: inputs.row)
        let full = ExportService.renderRowImage(
            row: inputs.row,
            screenshotImages: inputs.images,
            localeCode: inputs.localeCode,
            localeState: inputs.localeState,
            displayScale: displayScale
        )

        // Persist for reuse across launches. Awaited (off-main) so the cache is reliably on
        // disk by the time we return; the bitmap was rendered directly at thumbnail scale.
        let url = PersistenceService.thumbnailURL(project.id)
        let modifiedAt = project.modifiedAt
        await Task.detached(priority: .utility) { writeDiskCache(full, to: url, modifiedAt: modifiedAt) }.value

        return store(Image(nsImage: full), for: key)
    }

    @discardableResult
    private static func store(_ image: Image, for key: Key) -> Image {
        // Drop any older snapshot for this project so the cache doesn't grow per edit.
        cache = cache.filter { $0.key.id != key.id }
        cache[key] = image
        return image
    }

    /// Loads + decodes a project's first non-empty row and its referenced images, downsampled.
    /// `nonisolated` so it can run off the main actor.
    nonisolated private static func loadRenderInputs(for projectId: UUID) -> RenderInputs? {
        guard let data = PersistenceService.loadProject(projectId),
              let row = data.rows.first(where: { !$0.templates.isEmpty }) ?? data.rows.first,
              !row.templates.isEmpty
        else { return nil }

        let localeState = data.localeState ?? .default
        let localeCode = localeState.activeLocaleCode
        let imageMaxDimension = thumbnailImageMaxDimension(for: row)
        let images = loadImages(
            fileNames: referencedFileNames(row: row, localeState: localeState, localeCode: localeCode),
            projectId: projectId,
            maxDimension: imageMaxDimension
        )
        return RenderInputs(row: row, images: images, localeCode: localeCode, localeState: localeState)
    }

    nonisolated private static func thumbnailDisplayScale(for row: ScreenshotRow) -> CGFloat {
        let count = max(row.templates.count, 1)
        let rowWidth = row.templateWidth * CGFloat(count)
        let rowHeight = row.templateHeight
        guard rowWidth > 0, rowHeight > 0 else { return 1.0 }

        // Match the card's scaledToFill behavior: the rendered bitmap must be at least this
        // wide and tall after aspect-fill, otherwise tall or very wide projects look soft.
        let scale = max(targetDisplaySize.width / rowWidth, targetDisplaySize.height / rowHeight)
        return min(1.0, scale)
    }

    nonisolated private static func thumbnailImageMaxDimension(for row: ScreenshotRow) -> CGFloat {
        let count = max(row.templates.count, 1)
        let scale = thumbnailDisplayScale(for: row)
        let renderWidth = row.templateWidth * CGFloat(count) * scale
        let renderHeight = row.templateHeight * scale
        return max(ceil(max(renderWidth, renderHeight)), targetDisplaySize.width)
    }

    nonisolated private static func referencedFileNames(row: ScreenshotRow, localeState: LocaleState, localeCode: String) -> Set<String> {
        var result = Set<String>()
        if let f = row.backgroundImageConfig.fileName { result.insert(f) }
        for template in row.templates {
            if let f = template.backgroundImageConfig.fileName { result.insert(f) }
        }
        for shape in row.shapes {
            for f in shape.allImageFileNames { result.insert(f) }
        }
        if let overrides = localeState.overrides[localeCode] {
            for override in overrides.values {
                if let f = override.overrideImageFileName { result.insert(f) }
            }
        }
        return result
    }

    nonisolated private static func loadImages(fileNames: Set<String>, projectId: UUID, maxDimension: CGFloat) -> [String: NSImage] {
        let dir = PersistenceService.resourcesDir(projectId)
        var images: [String: NSImage] = [:]
        for name in fileNames {
            let url = dir.appendingPathComponent(name)
            // Read through PersistenceService so iCloud-backed resources are coordinated and
            // download-kicked off the main actor before CGImageSource decodes the thumbnail.
            guard let data = PersistenceService.readData(from: url) else { continue }
            if let image = AppState.downsampledImage(from: data, maxDimension: maxDimension)
                ?? NSImage(data: data) {
                images[name] = image
            }
        }
        return images
    }

    /// A cached PNG counts as fresh only if its stamped mod-date is at least as new as the
    /// project's last edit. The mod-date is set to the project's `modifiedAt` at write time (see
    /// `writeDiskCache`), NOT the wall-clock write time — otherwise a thumbnail rendered locally
    /// at a later wall-clock moment than an incoming (older-timestamped) iCloud edit would look
    /// "fresh" and the synced change would never re-render. The 1s slack absorbs filesystem
    /// mod-date rounding; real edits that change a thumbnail are never that close together.
    nonisolated private static func diskCachedImage(for project: Project) -> NSImage? {
        let url = PersistenceService.thumbnailURL(project.id)
        guard let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
              mtime.timeIntervalSince(project.modifiedAt) >= -1 else { return nil }
        return NSImage(contentsOf: url)
    }

    nonisolated private static func writeDiskCache(_ image: NSImage, to url: URL, modifiedAt: Date) {
        guard let data = ExportImageEncoder.pngData(from: image) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        // Stamp the file's mod-date to the project's logical edit time so freshness compares
        // content versions, not write time.
        try? fm.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
    }
}
