import SwiftUI
import UniformTypeIdentifiers

extension EditorRowView {
    func simulatorCaptureAction(for shape: CanvasShapeModel) -> (() -> Void)? {
        #if DEBUG && os(macOS)
        guard shape.type == .device else { return nil }
        return {
            if SimulatorCaptureService.isHelperInstalled {
                state.captureFromSimulator(intoShape: shape.id) { message in
                    activeAlert = .simulatorCaptureFailed(message)
                }
            } else {
                activeAlert = .simulatorInstallPrompt(shapeId: shape.id)
            }
        }
        #else
        return nil
        #endif
    }

    func revealImageAction(for shape: CanvasShapeModel) -> (() -> Void)? {
        #if os(macOS)
        guard shape.type == .device || shape.type == .image,
              let fileName = shape.displayImageFileName,
              let projectId = state.activeProjectId else { return nil }
        let url = PersistenceService.resourcesDir(projectId).appendingPathComponent(fileName)
        return { PlatformReveal.inFileViewer([url]) }
        #else
        return nil
        #endif
    }

    func handleCanvasDrop(_ providers: [NSItemProvider], at displayLocation: CGPoint, displayScale ds: CGFloat) -> Bool {
        guard !providers.isEmpty else { return false }
        let dropX = displayLocation.x / ds
        let dropY = displayLocation.y / ds
        if routeFolderDrop(providers, fallback: { provider in
            ItemProviderImageLoader.loadImage(from: provider) { image in
                guard let image else { return }
                self.createImageShape(image: image, modelX: dropX, modelY: dropY, source: .dropCanvas)
            }
        }) { return true }

        var svgProviders: [NSItemProvider] = []
        var imageProviders: [NSItemProvider] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.svg.identifier) {
                svgProviders.append(provider)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
                      provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                imageProviders.append(provider)
            }
        }

        var handled = false
        let baseX = displayLocation.x / ds
        let baseY = displayLocation.y / ds

        for (i, provider) in svgProviders.enumerated() {
            let modelX = baseX + CGFloat(i) * 60
            let modelY = baseY + CGFloat(i) * 60
            // Explicitly @Sendable: NSItemProvider calls back off the main queue, and a bare
            // closure literal would be inferred main-isolated under this target's default
            // actor isolation. The URL dies with the callback, so parse here and hop after.
            let report = reportDropFailure
            provider.loadFileRepresentation(forTypeIdentifier: UTType.svg.identifier) { @Sendable url, error in
                guard let url = url,
                      let content = try? String(contentsOf: url, encoding: .utf8) else {
                    let failure = DropFailure.svg(error)
                    Task { @MainActor in report(failure) }
                    return
                }
                let sanitized = SvgHelper.sanitize(content)
                guard let data = sanitized.data(using: .utf8),
                      let image = NSImage(data: data) else {
                    Task { @MainActor in report(.unrenderableSvg) }
                    return
                }
                let size = SvgHelper.parseSize(sanitized, fallbackImage: image)
                Task { @MainActor in
                    state.insertSvgShape(
                        content: sanitized,
                        naturalSize: size,
                        inRow: row.id,
                        at: CGPoint(x: modelX, y: modelY)
                    )
                }
            }
            handled = true
        }

        // Handle image providers: batch = one per template, single = at drop location
        if imageProviders.count > 1 {
            handleBatchImageDrop(imageProviders)
            handled = true
        } else if let provider = imageProviders.first {
            let modelX = baseX
            let modelY = baseY
            ItemProviderImageLoader.loadImage(from: provider) { image in
                guard let image else { return }
                self.createImageShape(image: image, modelX: modelX, modelY: modelY, source: .dropCanvas)
            }
            handled = true
        }

        return handled
    }

    func handleBatchImageDrop(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        var loadedImages: [(Int, NSImage)] = []
        let lock = NSLock()

        for (i, provider) in providers.enumerated() {
            group.enter()
            ItemProviderImageLoader.loadImage(from: provider) { image in
                if let image {
                    lock.lock()
                    loadedImages.append((i, image))
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [self] in
            let sources = loadedImages.sorted(by: { $0.0 < $1.0 }).map { ImageImportSource(image: $0.1) }
            guard !sources.isEmpty else { return }
            let cap = store.isProUnlocked ? nil : PurchaseService.freeMaxTemplatesPerRow
            Task { @MainActor in
                let imported = await state.batchImportImages(sources, into: row.id, maxTemplatesPerRow: cap, source: .dropRow)
                if imported < sources.count {
                    store.presentPaywall(for: .templateLimit)
                }
            }
        }
    }

    // MARK: - Localized folder import

    /// A single dropped folder is a localized import, not an image. Finder may describe it only as
    /// `public.file-url`, so the URL is loaded and checked; anything that isn't a directory takes
    /// the single-image path it would have taken anyway.
    private func routeFolderDrop(_ providers: [NSItemProvider], fallback: @escaping (NSItemProvider) -> Void) -> Bool {
        #if os(macOS)
        guard providers.count == 1, let provider = providers.first,
              provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
              !provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
              !provider.hasItemConformingToTypeIdentifier(UTType.svg.identifier)
        else { return false }
        let pending = PendingFolderDrop(provider: provider, begin: beginLocaleFolderImport, fallback: fallback)
        _ = provider.loadObject(ofClass: URL.self) { @Sendable url, _ in
            let isDirectory = url.flatMap { try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory } ?? false
            Task { @MainActor in pending.finish(url: url, isDirectory: isDirectory) }
        }
        return true
        #else
        return false
        #endif
    }

    func chooseLocaleFolder() {
        guard let folder = FilePicker.pickLocalizedScreenshotsFolder() else { return }
        beginLocaleFolderImport(folder)
    }

    func beginLocaleFolderImport(_ folder: URL) {
        let rowSize = CGSize(width: row.templateWidth, height: row.templateHeight)
        let plan = LocaleFolderImportPlanner.plan(
            folder: folder,
            projectLocaleCodes: state.localeState.locales.map(\.code),
            rowSize: rowSize
        )
        CrashReportingService.breadcrumb(.media, "locale folder planned", data: [
            "images": plan.imageCount, "locales": plan.batches.count, "skipped": plan.skippedForSize.count,
        ])
        localeFolderImport = LocaleFolderImportRequest(folder: folder, rowId: row.id, rowSize: rowSize, plan: plan)
    }

    func performLocaleFolderImport(_ request: LocaleFolderImportRequest, addingLocales: [LocaleDefinition]) {
        let existingCodes = state.localeState.locales.map(\.code)
        var seen = Set(existingCodes)
        let newLocales = addingLocales.filter { seen.insert($0.code).inserted }
        let plan = newLocales.isEmpty ? request.plan : LocaleFolderImportPlanner.plan(
            folder: request.folder,
            projectLocaleCodes: existingCodes + newLocales.map(\.code),
            rowSize: request.rowSize
        )
        // By reference: the plan already read each header, and the bytes are copied from
        // `sourceURL`, so reading every file here would only stall the main thread.
        let batches = plan.batches.map { batch in
            (localeCode: batch.localeCode, sources: batch.files.compactMap { url in
                (NSImage(byReferencing: url) as NSImage?).map { ImageImportSource(image: $0, sourceURL: url) }
            })
        }
        let sourceCount = batches.reduce(0) { $0 + $1.sources.count }
        let cap = store.isProUnlocked ? nil : PurchaseService.freeMaxTemplatesPerRow
        Task { @MainActor in
            let imported = await state.importLocalizedScreenshots(
                batches, into: request.rowId, addingLocales: newLocales, maxTemplatesPerRow: cap
            )
            if cap != nil && imported < sourceCount {
                store.presentPaywall(for: .templateLimit)
            }
        }
    }

}

/// Carries the drop's provider and continuations across NSItemProvider's background callback;
/// main-actor isolated, so the callback can hold it without sending either across actors.
@MainActor
private final class PendingFolderDrop {
    private let provider: NSItemProvider
    private let begin: (URL) -> Void
    private let fallback: (NSItemProvider) -> Void

    init(provider: NSItemProvider, begin: @escaping (URL) -> Void, fallback: @escaping (NSItemProvider) -> Void) {
        self.provider = provider
        self.begin = begin
        self.fallback = fallback
    }

    func finish(url: URL?, isDirectory: Bool) {
        if let url, isDirectory {
            begin(url)
        } else {
            fallback(provider)
        }
    }
}
