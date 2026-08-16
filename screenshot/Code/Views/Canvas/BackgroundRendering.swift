import SwiftUI

// Rendering for `BackgroundFillable`. Kept out of `Models/` so the persisted background
// shape and the editor↔export renderer are not read as one thing.

extension BackgroundFillable {
    @ViewBuilder
    func backgroundFillView(image: NSImage? = nil, modelSize: CGSize? = nil) -> some View {
        switch backgroundStyle {
        case .color:
            Rectangle().fill(bgColor)
        case .gradient:
            gradientConfig.gradientFill
        case .image:
            if image != nil || backgroundImageConfig.svgContent != nil {
                ZStack {
                    Rectangle().fill(bgColor)
                    BackgroundImageView(image: image, config: backgroundImageConfig, modelSize: modelSize)
                }
            } else {
                Rectangle().fill(bgColor)
            }
        }
    }

    @ViewBuilder
    func resolvedBackgroundView(screenshotImages: [String: NSImage], modelSize: CGSize? = nil) -> some View {
        let bgImage = backgroundImageConfig.fileName.flatMap { screenshotImages[$0] }
        backgroundFillView(image: bgImage, modelSize: modelSize)
    }

}

struct BackgroundImageView: View {
    let image: NSImage?
    let config: BackgroundImageConfig
    var modelSize: CGSize?

    @State private var cachedSvgImage: NSImage?
    @State private var svgCacheKey: String = ""

    init(image: NSImage?, config: BackgroundImageConfig, modelSize: CGSize? = nil) {
        self.image = image
        self.config = config
        self.modelSize = modelSize
        // Eagerly render SVG so export doesn't depend on onAppear
        if image == nil, let svgContent = config.svgContent {
            let rendered = config.renderSvgImage(modelSize: modelSize)
            let fillKey = config.fillMode == .tile ? "tile" : "scaled"
            let refDim = max(modelSize?.width ?? 1200, modelSize?.height ?? 1200)
            _cachedSvgImage = State(initialValue: rendered)
            _svgCacheKey = State(initialValue: "\(svgContent.hashValue)-\(fillKey)-\(Int(refDim))")
        } else {
            _cachedSvgImage = State(initialValue: nil)
            _svgCacheKey = State(initialValue: "")
        }
    }

    var body: some View {
        // Avoid GeometryReader: its size-dependent child isn't reliably resolved before an
        // offscreen snapshot (NSHostingView/ImageRenderer) captures, which left image
        // backgrounds blank intermittently in export/showcase previews. fill/fit/stretch size
        // themselves to the parent frame; tile reads its draw size from Canvas synchronously.
        Group {
            if let resolvedImage = image ?? cachedSvgImage {
                renderFillMode(image: resolvedImage)
            }
        }
        // Stay greedy (fill the parent) even before the image resolves — matches the old
        // GeometryReader so callers without an explicit frame don't collapse to zero size.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(config.opacity)
        .onChange(of: config.svgContent) { updateSvgCache() }
        .onChange(of: config.fillMode == .tile) { updateSvgCache() }
    }

    private func updateSvgCache() {
        guard image == nil, let svgContent = config.svgContent else {
            cachedSvgImage = nil
            svgCacheKey = ""
            return
        }
        let refDim = max(modelSize?.width ?? 1200, modelSize?.height ?? 1200)
        let fillKey = config.fillMode == .tile ? "tile" : "scaled"
        let key = "\(svgContent.hashValue)-\(fillKey)-\(Int(refDim))"
        guard key != svgCacheKey else { return }
        svgCacheKey = key
        cachedSvgImage = config.renderSvgImage(modelSize: modelSize)
    }

    @ViewBuilder
    private func renderFillMode(image: NSImage) -> some View {
        let swiftImage = Image(nsImage: image)
        switch config.fillMode {
        case .fill:
            swiftImage
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        case .fit:
            swiftImage
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .stretch:
            swiftImage
                .resizable()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .tile:
            tileView(image: image)
        }
    }

    @ViewBuilder
    private func tileView(image: NSImage) -> some View {
        let scaleX = max(config.tileScaleX, 0.1)
        let scaleY = max(config.tileScaleY, 0.1)
        let imgW = image.size.width * scaleX
        let imgH = image.size.height * scaleY
        if imgW > 0, imgH > 0 {
            Canvas { context, size in
                // `size` is the rendered draw size (display-space in editor, model-space in
                // export); `refSize` keeps tile counts driven by model space for parity.
                let refSize = modelSize ?? size
                guard refSize.width > 0, refSize.height > 0 else { return }
                let spacingX = config.tileSpacingX
                let spacingY = config.tileSpacingY
                let offsetX = config.tileOffsetX
                let offsetY = config.tileOffsetY
                let stepW = imgW * (1 + spacingX)
                let stepH = imgH * (1 + spacingY)
                let offW = imgW * offsetX
                let offH = imgH * offsetY
                let rawCols = max(1, Int(ceil((refSize.width + offW) / stepW)) + 1)
                let rawRows = max(1, Int(ceil((refSize.height + offH) / stepH)) + 1)
                let drawScale = rawCols * rawRows > 10_000
                    ? sqrt(Double(rawCols * rawRows) / 10_000.0) : 1.0
                let cols = max(1, Int(Double(rawCols) / drawScale))
                let rows = max(1, Int(Double(rawRows) / drawScale))
                let toDisplayX = size.width / refSize.width
                let toDisplayY = size.height / refSize.height
                // When spacing is near 0, add a small overlap to prevent
                // sub-pixel gaps caused by floating-point rounding.
                let overlapX: CGFloat = spacingX < 0.001 ? 0.5 : 0
                let overlapY: CGFloat = spacingY < 0.001 ? 0.5 : 0
                let tileW = imgW * toDisplayX + overlapX
                let tileH = imgH * toDisplayY + overlapY
                let resolved = context.resolve(Image(nsImage: image))
                for r in 0..<rows {
                    for c in 0..<cols {
                        let x = (CGFloat(c) * stepW - offW) * toDisplayX
                        let y = (CGFloat(r) * stepH - offH) * toDisplayY
                        let rect = CGRect(x: x, y: y, width: tileW, height: tileH)
                        context.draw(resolved, in: rect)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }
}

struct BackgroundBlurView<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let blurRadius: CGFloat
    let content: Content

    init(width: CGFloat, height: CGFloat, blurRadius: CGFloat, @ViewBuilder content: () -> Content) {
        self.width = width
        self.height = height
        self.blurRadius = blurRadius
        self.content = content()
    }

    var body: some View {
        content
            .compositingGroup()
            .blur(radius: blurRadius, opaque: true)
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
    }
}
