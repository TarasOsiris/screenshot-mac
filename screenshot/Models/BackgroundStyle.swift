import SwiftUI

enum BackgroundStyle: String, Codable, CaseIterable {
    case color
    case gradient
    case image
}

enum ImageFillMode: String, Codable, CaseIterable {
    case fill
    case fit
    case stretch
    case tile
}

struct BackgroundImageConfig: Codable, Equatable {
    var fileName: String?
    var fillMode: ImageFillMode
    var opacity: Double
    var tileSpacing: Double // 0-1 relative to image size
    var tileOffset: Double  // 0-1 relative to image size
    var tileScale: Double   // 0.1-3.0 scale factor for tile images

    enum CodingKeys: String, CodingKey {
        case fileName = "f", fillMode = "fm", opacity = "a"
        case tileSpacing = "ts", tileOffset = "to", tileScale = "tsc"
    }

    init(fileName: String? = nil, fillMode: ImageFillMode = .fill, opacity: Double = 1.0,
         tileSpacing: Double = 0.0, tileOffset: Double = 0.0, tileScale: Double = 1.0) {
        self.fileName = fileName
        self.fillMode = fillMode
        self.opacity = opacity
        self.tileSpacing = tileSpacing
        self.tileOffset = tileOffset
        self.tileScale = tileScale
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.flexContainer()
        fileName = try c.opt(String.self, "f", "fileName")
        fillMode = try c.opt(ImageFillMode.self, "fm", "fillMode") ?? .fill
        opacity = try c.opt(Double.self, "a", "opacity") ?? 1.0
        tileSpacing = try c.opt(Double.self, "ts", "tileSpacing") ?? 0.0
        tileOffset = try c.opt(Double.self, "to", "tileOffset") ?? 0.0
        tileScale = try c.opt(Double.self, "tsc", "tileScale") ?? 1.0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(fileName, forKey: .fileName)
        if fillMode != .fill { try c.encode(fillMode, forKey: .fillMode) }
        if opacity != 1.0 { try c.encode(opacity, forKey: .opacity) }
        if tileSpacing != 0 { try c.encode(tileSpacing, forKey: .tileSpacing) }
        if tileOffset != 0 { try c.encode(tileOffset, forKey: .tileOffset) }
        if tileScale != 1.0 { try c.encode(tileScale, forKey: .tileScale) }
    }
}

protocol BackgroundFillable {
    var backgroundStyle: BackgroundStyle { get }
    var bgColor: Color { get }
    var gradientConfig: GradientConfig { get }
    var backgroundImageConfig: BackgroundImageConfig { get }
}

extension BackgroundFillable {
    @ViewBuilder
    func backgroundFillView(image: NSImage? = nil, modelSize: CGSize? = nil) -> some View {
        switch backgroundStyle {
        case .color:
            Rectangle().fill(bgColor)
        case .gradient:
            gradientConfig.gradientFill
        case .image:
            if let image {
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
    let image: NSImage
    let config: BackgroundImageConfig
    var modelSize: CGSize?

    var body: some View {
        GeometryReader { geo in
            let swiftImage = Image(nsImage: image)

            switch config.fillMode {
            case .fill:
                swiftImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            case .fit:
                swiftImage
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geo.size.width, height: geo.size.height)
            case .stretch:
                swiftImage
                    .resizable()
                    .frame(width: geo.size.width, height: geo.size.height)
            case .tile:
                let scale = max(config.tileScale, 0.1)
                let imgW = image.size.width * scale
                let imgH = image.size.height * scale
                let refSize = modelSize ?? geo.size
                if imgW > 0, imgH > 0, refSize.width > 0, refSize.height > 0 {
                    let spacing = config.tileSpacing
                    let offset = config.tileOffset
                    let stepW = imgW * (1 + spacing)
                    let stepH = imgH * (1 + spacing)
                    let offW = imgW * offset
                    let offH = imgH * offset
                    let rawCols = max(1, Int(ceil((refSize.width + offW) / stepW)) + 1)
                    let rawRows = max(1, Int(ceil((refSize.height + offH) / stepH)) + 1)
                    let drawScale = rawCols * rawRows > 10_000
                        ? sqrt(Double(rawCols * rawRows) / 10_000.0) : 1.0
                    let cols = max(1, Int(Double(rawCols) / drawScale))
                    let rows = max(1, Int(Double(rawRows) / drawScale))
                    let toDisplay = geo.size.width / refSize.width
                    // When spacing is near 0, add a small overlap to prevent
                    // sub-pixel gaps caused by floating-point rounding.
                    let overlap: CGFloat = spacing < 0.001 ? 0.5 : 0
                    let tileW = imgW * toDisplay + overlap
                    let tileH = imgH * toDisplay + overlap
                    Canvas { context, size in
                        let resolved = context.resolve(Image(nsImage: image))
                        for r in 0..<rows {
                            for c in 0..<cols {
                                let x = (CGFloat(c) * stepW - offW) * toDisplay
                                let y = (CGFloat(r) * stepH - offH) * toDisplay
                                let rect = CGRect(x: x, y: y, width: tileW, height: tileH)
                                context.draw(resolved, in: rect)
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                }
            }
        }
        .opacity(config.opacity)
    }
}

struct GradientColorStop: Codable, Equatable, Identifiable {
    var id: UUID
    var colorData: CodableColor
    var location: Double // 0.0 to 1.0

    enum CodingKeys: String, CodingKey {
        case id, colorData = "c", location = "l"
    }

    init(id: UUID = UUID(), color: Color, location: Double) {
        self.id = id
        self.colorData = CodableColor(color)
        self.location = min(max(location, 0), 1)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.flexContainer()
        id = try c.decode(UUID.self, "id")
        colorData = try c.decode(CodableColor.self, "c", "colorData")
        location = try c.decode(Double.self, "l", "location")
    }

    var color: Color {
        get { colorData.color }
        set { colorData = CodableColor(newValue) }
    }
}

enum GradientType: String, Codable, CaseIterable {
    case linear
    case radial
    case angular
}

struct GradientConfig: Codable, Equatable {
    var stops: [GradientColorStop]
    var angle: Double // degrees
    var gradientType: GradientType
    var centerX: Double // 0.0-1.0, used by radial and angular
    var centerY: Double // 0.0-1.0, used by radial and angular

    init(stops: [GradientColorStop], angle: Double = 135, gradientType: GradientType = .linear,
         centerX: Double = 0.5, centerY: Double = 0.5) {
        self.stops = stops.sorted { $0.location < $1.location }
        self.angle = angle
        self.gradientType = gradientType
        self.centerX = centerX
        self.centerY = centerY
    }

    init(color1: Color = Color(red: 0.4, green: 0.49, blue: 0.92),
         color2: Color = Color(red: 0.46, green: 0.29, blue: 0.64),
         angle: Double = 135,
         gradientType: GradientType = .linear) {
        self.init(stops: [
            GradientColorStop(color: color1, location: 0),
            GradientColorStop(color: color2, location: 1),
        ], angle: angle, gradientType: gradientType)
    }

    enum CodingKeys: String, CodingKey {
        case stops = "s", angle = "a", gradientType = "gt"
        case centerX = "cx", centerY = "cy"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.flexContainer()
        angle = try c.decode(Double.self, "a", "angle")
        gradientType = try c.opt(GradientType.self, "gt", "gradientType") ?? .linear
        centerX = try c.opt(Double.self, "cx", "centerX") ?? 0.5
        centerY = try c.opt(Double.self, "cy", "centerY") ?? 0.5

        if let stops = try c.opt([GradientColorStop].self, "s", "stops") {
            self.stops = stops.sorted { $0.location < $1.location }
        } else {
            // Migrate from old color1Data/color2Data format
            let c1 = try c.decode(CodableColor.self, "color1Data")
            let c2 = try c.decode(CodableColor.self, "color2Data")
            self.stops = [
                GradientColorStop(color: c1.color, location: 0),
                GradientColorStop(color: c2.color, location: 1),
            ]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(stops, forKey: .stops)
        try c.encode(angle, forKey: .angle)
        if gradientType != .linear { try c.encode(gradientType, forKey: .gradientType) }
        if centerX != 0.5 { try c.encode(centerX, forKey: .centerX) }
        if centerY != 0.5 { try c.encode(centerY, forKey: .centerY) }
    }

    private var radians: Double {
        (angle - 90) * .pi / 180
    }

    var startPoint: UnitPoint {
        UnitPoint(x: 0.5 - cos(radians) * 0.5, y: 0.5 - sin(radians) * 0.5)
    }

    var endPoint: UnitPoint {
        UnitPoint(x: 0.5 + cos(radians) * 0.5, y: 0.5 + sin(radians) * 0.5)
    }

    var swiftUIStops: [Gradient.Stop] {
        stops.map { Gradient.Stop(color: $0.color, location: $0.location) }
    }

    var linearGradient: LinearGradient {
        LinearGradient(
            stops: swiftUIStops,
            startPoint: startPoint,
            endPoint: endPoint
        )
    }

    @ViewBuilder
    var gradientFill: some View {
        switch gradientType {
        case .linear:
            Rectangle().fill(linearGradient)
        case .radial:
            // GeometryReader reads the actual rendered frame size (display-space in editor,
            // model-space in export) so endRadius is always correct for the view's coordinates.
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let cx = w * centerX
                let cy = h * centerY
                let dx = max(cx, w - cx)
                let dy = max(cy, h - cy)
                let endRadius = sqrt(dx * dx + dy * dy)
                Rectangle().fill(RadialGradient(
                    stops: swiftUIStops,
                    center: UnitPoint(x: centerX, y: centerY),
                    startRadius: 0,
                    endRadius: endRadius
                ))
            }
        case .angular:
            Rectangle().fill(AngularGradient(
                stops: swiftUIStops,
                center: UnitPoint(x: centerX, y: centerY),
                angle: .degrees(angle - 90)
            ))
        }
    }

    @discardableResult
    mutating func addStop(color: Color, at location: Double) -> UUID {
        let stop = GradientColorStop(color: color, location: location)
        stops.append(stop)
        stops.sort { $0.location < $1.location }
        return stop.id
    }

    mutating func removeStop(id: UUID) {
        guard stops.count > 2 else { return }
        stops.removeAll { $0.id == id }
    }

    mutating func reverseStops() {
        for i in stops.indices {
            stops[i].location = 1.0 - stops[i].location
        }
        stops.reverse()
    }
}

struct GradientPreset: Identifiable {
    let id = UUID()
    let label: String
    let config: GradientConfig

    init(label: String, color1: Color, color2: Color, angle: Double) {
        self.label = label
        self.config = GradientConfig(color1: color1, color2: color2, angle: angle)
    }

    init(label: String, stops: [GradientColorStop], angle: Double) {
        self.label = label
        self.config = GradientConfig(stops: stops, angle: angle)
    }
}

let gradientPresets: [GradientPreset] = [
    GradientPreset(label: "Ocean", color1: Color(red: 0.4, green: 0.49, blue: 0.92), color2: Color(red: 0.46, green: 0.29, blue: 0.64), angle: 135),
    GradientPreset(label: "Sunset", color1: Color(red: 0.94, green: 0.58, blue: 0.98), color2: Color(red: 0.96, green: 0.34, blue: 0.42), angle: 135),
    GradientPreset(label: "Peach", color1: Color(red: 0.96, green: 0.83, blue: 0.40), color2: Color(red: 0.99, green: 0.63, blue: 0.52), angle: 135),
    GradientPreset(label: "Mint", color1: Color(red: 0.63, green: 0.77, blue: 0.99), color2: Color(red: 0.76, green: 0.91, blue: 0.98), angle: 135),
    GradientPreset(label: "Berry", color1: Color(red: 0.63, green: 0.55, blue: 0.82), color2: Color(red: 0.98, green: 0.76, blue: 0.92), angle: 135),
    GradientPreset(label: "Flame", color1: Color(red: 0.97, green: 0.21, blue: 0.0), color2: Color(red: 0.98, green: 0.83, blue: 0.14), angle: 135),
    GradientPreset(label: "Sky", color1: Color(red: 0.54, green: 0.97, blue: 1.0), color2: Color(red: 0.40, green: 0.65, blue: 1.0), angle: 135),
    GradientPreset(label: "Forest", color1: Color(red: 0.07, green: 0.60, blue: 0.56), color2: Color(red: 0.22, green: 0.94, blue: 0.49), angle: 135),
    GradientPreset(label: "Night", color1: Color(red: 0.06, green: 0.13, blue: 0.15), color2: Color(red: 0.17, green: 0.33, blue: 0.39), angle: 135),
    GradientPreset(label: "Rose", color1: Color(red: 0.93, green: 0.61, blue: 0.65), color2: Color(red: 1.0, green: 0.87, blue: 0.88), angle: 135),
    GradientPreset(label: "Indigo", color1: Color(red: 0.26, green: 0.22, blue: 0.79), color2: Color(red: 0.39, green: 0.40, blue: 0.95), angle: 135),
    GradientPreset(label: "Emerald", color1: Color(red: 0.02, green: 0.59, blue: 0.41), color2: Color(red: 0.20, green: 0.83, blue: 0.60), angle: 135),
    // Multi-stop presets
    GradientPreset(label: "Rainbow", stops: [
        GradientColorStop(color: Color(red: 1, green: 0.2, blue: 0.2), location: 0),
        GradientColorStop(color: Color(red: 1, green: 0.8, blue: 0.2), location: 0.25),
        GradientColorStop(color: Color(red: 0.2, green: 0.9, blue: 0.4), location: 0.5),
        GradientColorStop(color: Color(red: 0.3, green: 0.5, blue: 1), location: 0.75),
        GradientColorStop(color: Color(red: 0.7, green: 0.3, blue: 0.9), location: 1),
    ], angle: 90),
    GradientPreset(label: "Aurora", stops: [
        GradientColorStop(color: Color(red: 0.05, green: 0.1, blue: 0.3), location: 0),
        GradientColorStop(color: Color(red: 0.1, green: 0.6, blue: 0.5), location: 0.4),
        GradientColorStop(color: Color(red: 0.4, green: 0.9, blue: 0.6), location: 0.7),
        GradientColorStop(color: Color(red: 0.9, green: 0.95, blue: 0.8), location: 1),
    ], angle: 0),
    GradientPreset(label: "Warm Sunset", stops: [
        GradientColorStop(color: Color(red: 0.15, green: 0.05, blue: 0.3), location: 0),
        GradientColorStop(color: Color(red: 0.8, green: 0.2, blue: 0.4), location: 0.4),
        GradientColorStop(color: Color(red: 1, green: 0.6, blue: 0.2), location: 0.75),
        GradientColorStop(color: Color(red: 1, green: 0.9, blue: 0.5), location: 1),
    ], angle: 0),
    GradientPreset(label: "Deep Sea", stops: [
        GradientColorStop(color: Color(red: 0.0, green: 0.05, blue: 0.15), location: 0),
        GradientColorStop(color: Color(red: 0.0, green: 0.2, blue: 0.5), location: 0.5),
        GradientColorStop(color: Color(red: 0.2, green: 0.7, blue: 0.8), location: 1),
    ], angle: 180),
]
