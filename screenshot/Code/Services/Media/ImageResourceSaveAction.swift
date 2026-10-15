import Foundation

/// Which image write failed, spelled as whole sentences so each reads naturally once translated.
enum ImageResourceSaveAction {
    case saveScreenshot
    case saveFillImage
    case saveBackgroundImage

    var encodeFailedMessage: String {
        switch self {
        case .saveScreenshot: String(localized: "Failed to save screenshot: could not encode image.")
        case .saveFillImage: String(localized: "Failed to save fill image: could not encode image.")
        case .saveBackgroundImage: String(localized: "Failed to save background image: could not encode image.")
        }
    }

    func writeFailedMessage(_ reason: String) -> String {
        switch self {
        case .saveScreenshot:
            String(localized: "Failed to save screenshot: \(reason)", comment: "The placeholder is the system's error description.")
        case .saveFillImage:
            String(localized: "Failed to save fill image: \(reason)", comment: "The placeholder is the system's error description.")
        case .saveBackgroundImage:
            String(localized: "Failed to save background image: \(reason)", comment: "The placeholder is the system's error description.")
        }
    }
}
