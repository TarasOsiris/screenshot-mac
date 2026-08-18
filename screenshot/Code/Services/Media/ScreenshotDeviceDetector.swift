#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation

/// Works out which device an imported screenshot came from, and which catalog frame to wrap it in.
///
/// None of this touches the document — it reads an image's pixel dimensions and the row it's
/// landing in — so it lived on `AppState` only because that is where the import happens.
enum ScreenshotDeviceDetector {
    static func preferredImportFrame(for image: NSImage, in row: ScreenshotRow, detectedCategory: DeviceCategory) -> DeviceFrame? {
        let isLandscape = imageIsLandscape(image)

        if let frameId = mostCommonDeviceFrameId(in: row, matching: detectedCategory),
           let frame = DeviceFrameCatalog.frame(for: frameId) {
            return landscapeVariant(of: frame, isLandscape: isLandscape)
        }

        if let defaultFrameId = row.defaultDeviceFrameId,
           let defaultFrame = DeviceFrameCatalog.frame(for: defaultFrameId),
           defaultFrame.fallbackCategory == detectedCategory {
            return landscapeVariant(of: defaultFrame, isLandscape: isLandscape)
        }

        // The Apple categories' abstract frames are drawn portrait-only, so a landscape shot
        // has to be promoted to a real catalog frame.
        guard isLandscape == true else { return nil }
        return DeviceFrameCatalog.firstFrame(for: detectedCategory, isLandscape: true)
    }

    private static func landscapeVariant(of frame: DeviceFrame, isLandscape: Bool?) -> DeviceFrame {
        guard let isLandscape, isLandscape != frame.isLandscape else { return frame }
        return DeviceFrameCatalog.variant(forFrameId: frame.id, isLandscape: isLandscape) ?? frame
    }

    private static func mostCommonDeviceFrameId(in row: ScreenshotRow, matching category: DeviceCategory) -> String? {
        var counts: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]

        for (index, shape) in row.shapes.enumerated() where shape.type == .device {
            guard let frameId = shape.deviceFrameId,
                  let frame = DeviceFrameCatalog.frame(for: frameId),
                  frame.fallbackCategory == category else { continue }
            counts[frameId, default: 0] += 1
            firstSeen[frameId] = firstSeen[frameId] ?? index
        }

        return counts.max { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value < rhs.value
            }
            return (firstSeen[lhs.key] ?? .max) > (firstSeen[rhs.key] ?? .max)
        }?.key
    }

    private static func imageIsLandscape(_ image: NSImage) -> Bool? {
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return rep.pixelsWide > rep.pixelsHigh
        }
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        return image.size.width > image.size.height
    }

    // Known screenshot pixel sizes (portrait "WxH") → device category
    private static let knownScreenshotSizes: [String: DeviceCategory] = {
        var map = [String: DeviceCategory]()
        // iPhone
        for size in [
            "750x1334",   // iPhone SE / 8
            "828x1792",   // iPhone XR / 11
            "1080x1920",  // iPhone 6/7/8 Plus
            "1125x2436",  // iPhone X / XS / 11 Pro
            "1080x2340",  // iPhone 12 mini / 13 mini
            "1170x2532",  // iPhone 12 / 13 / 14
            "1179x2556",  // iPhone 14 Pro / 15 / 16
            "1206x2622",  // iPhone 16 Pro / 17 / 17 Pro
            "1260x2736",  // iPhone Air
            "1242x2688",  // iPhone XS Max / 11 Pro Max
            "1284x2778",  // iPhone 12/13 Pro Max
            "1290x2796",  // iPhone 14 Pro Max / 15 Pro Max / 16 Plus
            "1320x2868",  // iPhone 16 Pro Max / 17 Pro Max
        ] { map[size] = .iphone }
        // iPad Pro 11"
        for size in [
            "1668x2388",  // iPad Pro 11" (3rd/4th gen)
            "1668x2420",  // iPad Pro 11" (M4)
        ] { map[size] = .ipadPro11 }
        // iPad Pro 13"
        for size in [
            "2048x2732",  // iPad Pro 12.9" (3rd-6th gen)
            "2064x2752",  // iPad Pro 13" (M4)
        ] { map[size] = .ipadPro13 }
        return map
    }()

    /// Detect if an image looks like a device screenshot. Returns the matching category or nil.
    static func detectScreenshotDevice(_ image: NSImage) -> DeviceCategory? {
        guard let rep = image.representations.first else { return nil }
        let pw = rep.pixelsWide
        let ph = rep.pixelsHigh
        guard pw > 0, ph > 0 else { return nil }
        // Normalize to portrait for lookup
        let (w, h) = pw > ph ? (ph, pw) : (pw, ph)
        if let category = knownScreenshotSizes["\(w)x\(h)"] { return category }
        // Heuristic fallback for phones
        let ratio = CGFloat(h) / CGFloat(w)
        if w >= 640 && w <= 1600 && ratio >= 1.7 && ratio <= 2.4 { return .iphone }
        // Heuristic fallback for iPads
        if w >= 1600 && w <= 2200 && ratio >= 1.2 && ratio <= 1.5 { return w >= 2000 ? .ipadPro13 : .ipadPro11 }
        return nil
    }
}
