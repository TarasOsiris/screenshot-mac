// Renders the DMG window background at 1x and 2x: swift make-background.swift <out-dir>
import AppKit

let size = NSSize(width: 640, height: 400)
let appCenter = NSPoint(x: 170, y: 200)
let applicationsCenter = NSPoint(x: 470, y: 200)
let brand = NSColor(srgbRed: 0.16, green: 0.42, blue: 0.96, alpha: 1)

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    let bitmapContext = NSGraphicsContext(bitmapImageRep: rep)!
    // Lay out top-down, matching Finder's icon coordinates; `flipped` keeps text upright.
    NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmapContext.cgContext, flipped: true)
    let flip = NSAffineTransform()
    flip.translateX(by: 0, yBy: size.height)
    flip.scaleX(by: 1, yBy: -1)
    flip.concat()

    NSGradient(colors: [
        NSColor(srgbRed: 0.97, green: 0.98, blue: 1.0, alpha: 1),
        NSColor(srgbRed: 0.89, green: 0.92, blue: 0.98, alpha: 1),
    ])!.draw(in: NSRect(origin: .zero, size: size), angle: 90)

    let title = NSAttributedString(string: "Drag Screenshot Bro to Applications", attributes: [
        .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
        .foregroundColor: NSColor(srgbRed: 0.11, green: 0.13, blue: 0.18, alpha: 1),
    ])
    title.draw(at: NSPoint(x: (size.width - title.size().width) / 2, y: 48))

    let subtitle = NSAttributedString(string: "Then open it from your Applications folder or Launchpad", attributes: [
        .font: NSFont.systemFont(ofSize: 13),
        .foregroundColor: NSColor(srgbRed: 0.35, green: 0.38, blue: 0.45, alpha: 1),
    ])
    subtitle.draw(at: NSPoint(x: (size.width - subtitle.size().width) / 2, y: 80))

    // Dashed arrow between the two icons (icons are 128 pt, labels sit below them).
    let startX = appCenter.x + 84, endX = applicationsCenter.x - 84, y = appCenter.y
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: startX, y: y))
    shaft.line(to: NSPoint(x: endX - 14, y: y))
    shaft.lineWidth = 4
    shaft.lineCapStyle = .round
    shaft.setLineDash([10, 9], count: 2, phase: 0)
    brand.withAlphaComponent(0.85).setStroke()
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: endX - 18, y: y - 13))
    head.line(to: NSPoint(x: endX, y: y))
    head.line(to: NSPoint(x: endX - 18, y: y + 13))
    head.lineWidth = 4.5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    let footer = NSAttributedString(string: "screenshotbro.app", attributes: [
        .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor(srgbRed: 0.45, green: 0.49, blue: 0.57, alpha: 1),
    ])
    footer.draw(at: NSPoint(x: (size.width - footer.size().width) / 2, y: size.height - 34))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try render(scale: 1).write(to: outDir.appendingPathComponent("background.png"))
try render(scale: 2).write(to: outDir.appendingPathComponent("background@2x.png"))
