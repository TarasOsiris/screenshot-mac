import SwiftUI
import UniformTypeIdentifiers

extension EditorRowView {
    func simulatorCaptureAction(for shape: CanvasShapeModel) -> (() -> Void)? {
        #if DEBUG && os(macOS)
        guard shape.type == .device else { return nil }
        return {
            if SimulatorCaptureService.isHelperInstalled {
                state.captureFromSimulator(intoShape: shape.id) { message in
                    simulatorCaptureError = message
                }
            } else {
                simulatorInstallPromptShapeId = shape.id
            }
        }
        #else
        return nil
        #endif
    }

    func handleCanvasDrop(_ providers: [NSItemProvider], at displayLocation: CGPoint, displayScale ds: CGFloat) -> Bool {
        guard !providers.isEmpty else { return false }

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
            provider.loadFileRepresentation(forTypeIdentifier: UTType.svg.identifier) { url, _ in
                guard let url = url,
                      let content = try? String(contentsOf: url, encoding: .utf8) else { return }
                let sanitized = SvgHelper.sanitize(content)
                guard let data = sanitized.data(using: .utf8),
                      let image = NSImage(data: data) else { return }
                let size = SvgHelper.parseSize(sanitized, fallbackImage: image)
                DispatchQueue.main.async {
                    state.selectRow(row.id)
                    let maxDim = row.svgMaxDimension
                    let scaledSize = SvgHelper.scaledSize(size, maxDim: maxDim)
                    let shape = CanvasShapeModel.defaultSvg(
                        centerX: modelX, centerY: modelY,
                        svgContent: sanitized, size: scaledSize
                    )
                    state.addShape(shape)
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
                self.createImageShape(image: image, modelX: modelX, modelY: modelY)
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
            let images = loadedImages.sorted(by: { $0.0 < $1.0 }).map(\.1)
            guard !images.isEmpty else { return }
            let cap = store.isProUnlocked ? nil : StoreService.freeMaxTemplatesPerRow
            let imported = state.batchImportImages(images, into: row.id, maxTemplatesPerRow: cap)
            if imported < images.count {
                store.presentPaywall(for: .templateLimit)
            }
        }
    }
}
