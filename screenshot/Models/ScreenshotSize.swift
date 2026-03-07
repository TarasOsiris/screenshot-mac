import Foundation
import SwiftUI

struct ScreenshotSize: Identifiable {
    let id = UUID()
    let width: CGFloat
    let height: CGFloat

    var label: String {
        "\(Int(width)) \u{00d7} \(Int(height))px"
    }

    var isLandscape: Bool {
        width > height
    }
}

struct DisplayCategory: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let sizes: [ScreenshotSize]
}

let displayCategories: [DisplayCategory] = [
    DisplayCategory(
        name: "iPhone 6.5\" Display",
        icon: "iphone",
        sizes: [
            ScreenshotSize(width: 1242, height: 2688),
            ScreenshotSize(width: 2688, height: 1242),
            ScreenshotSize(width: 1284, height: 2778),
            ScreenshotSize(width: 2778, height: 1284),
        ]
    ),
    DisplayCategory(
        name: "iPad 13\" Display",
        icon: "ipad",
        sizes: [
            ScreenshotSize(width: 2064, height: 2752),
            ScreenshotSize(width: 2752, height: 2064),
            ScreenshotSize(width: 2048, height: 2732),
            ScreenshotSize(width: 2732, height: 2048),
        ]
    ),
]

func parseSizeString(_ value: String) -> (width: CGFloat, height: CGFloat)? {
    let parts = value.split(separator: "x")
    guard parts.count == 2,
          let w = Double(parts[0]),
          let h = Double(parts[1]) else { return nil }
    return (CGFloat(w), CGFloat(h))
}
