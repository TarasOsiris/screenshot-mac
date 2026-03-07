import Foundation
import SwiftUI

struct ScreenshotTemplate: Identifiable, Codable {
    let id: UUID
    var backgroundColor: CodableColor

    init(id: UUID = UUID(), backgroundColor: Color = .blue) {
        self.id = id
        self.backgroundColor = CodableColor(backgroundColor)
    }

    var bgColor: Color {
        get { backgroundColor.color }
        set { backgroundColor = CodableColor(newValue) }
    }
}
