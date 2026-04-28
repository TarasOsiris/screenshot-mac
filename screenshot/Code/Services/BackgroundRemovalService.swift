import AppKit
import CoreImage
import Vision

enum BackgroundRemovalService {
    enum Failure: LocalizedError {
        case invalidImage
        case noSubjectFound

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return String(localized: "Could not load image.")
            case .noSubjectFound:
                return String(localized: "No foreground subject was detected in this image.")
            }
        }
    }

    /// Runs Vision's foreground-instance mask request on the image at `url` and returns a new
    /// image with everything except the detected foreground subject(s) made transparent, cropped
    /// tight to the subject's bounding box.
    static func removeBackground(at url: URL) throws -> NSImage {
        guard let ciImage = CIImage(contentsOf: url) else {
            throw Failure.invalidImage
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: ciImage)
        try handler.perform([request])

        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            throw Failure.noSubjectFound
        }

        let maskedPixelBuffer = try result.generateMaskedImage(
            ofInstances: result.allInstances,
            from: handler,
            croppedToInstancesExtent: true
        )

        let masked = CIImage(cvPixelBuffer: maskedPixelBuffer)
        let context = CIContext()
        guard let rendered = context.createCGImage(masked, from: masked.extent) else {
            throw Failure.invalidImage
        }
        return NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
    }
}
