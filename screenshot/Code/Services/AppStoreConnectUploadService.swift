import Foundation
import AppKit
import CryptoKit

enum AppStoreConnectUploadError: Error, LocalizedError {
    case renderFailed(rowLabel: String, index: Int)
    case noRowsSelected

    var errorDescription: String? {
        switch self {
        case .renderFailed(let label, let index):
            return "Failed to render screenshot \(index + 1) in row \(label)."
        case .noRowsSelected:
            return "No rows selected for upload."
        }
    }
}

struct ASCUploadLocalization {
    let id: String
    let label: String
    let localeCode: String
}

struct ASCUploadTarget: Identifiable {
    let id = UUID()
    let rowId: UUID
    let rowLabel: String
    let rowSize: CGSize
    let displayType: ASCDisplayType
    let localizations: [ASCUploadLocalization]
    let templateCount: Int
}

struct ASCUploadProgress {
    var totalSteps: Int
    var completedSteps: Int
    var currentLabel: String
}

@MainActor
final class AppStoreConnectUploadService {
    static let shared = AppStoreConnectUploadService()

    private let api: AppStoreConnectAPIService
    init(api: AppStoreConnectAPIService? = nil) { self.api = api ?? .shared }

    func upload(
        targets: [ASCUploadTarget],
        appState: AppState,
        progress: @escaping (ASCUploadProgress) -> Void
    ) async throws {
        guard !targets.isEmpty else { throw AppStoreConnectUploadError.noRowsSelected }

        let totalSteps = targets.reduce(0) { acc, target in
            acc + (target.templateCount * target.localizations.count)
        }
        var completedSteps = 0
        let fontFamilies = appState.availableFontFamilySet
        // Shared across all (target × localization) iterations so unchanged base-shape images
        // are decoded once per upload rather than once per locale.
        var imageCache: [String: NSImage] = [:]

        func emit(_ label: String) {
            progress(ASCUploadProgress(totalSteps: totalSteps, completedSteps: completedSteps, currentLabel: label))
        }

        emit("Starting…")

        for target in targets {
            guard let row = appState.rows.first(where: { $0.id == target.rowId }) else { continue }

            for localization in target.localizations {
                try Task.checkCancellation()
                let fileNames = appState.referencedImageFileNames(forRow: row, localeCode: localization.localeCode)
                let rowImages = appState.loadFullResolutionImages(fileNames: fileNames, cache: &imageCache)

                // Replace mode: dropping and recreating the set is one request vs. 1+N delete-each.
                let existingSets = try await api.listScreenshotSets(localizationId: localization.id)
                if let match = existingSets.first(where: { $0.attributes.screenshotDisplayType == target.displayType.rawValue }) {
                    try await api.deleteScreenshotSet(id: match.id)
                }
                let set = try await api.createScreenshotSet(
                    localizationId: localization.id,
                    displayType: target.displayType.rawValue
                )

                for templateIndex in 0..<target.templateCount {
                    try Task.checkCancellation()
                    let label = "\(target.rowLabel) · \(localization.label) · \(templateIndex + 1)/\(target.templateCount)"
                    emit(label)

                    let image = ExportService.renderSingleTemplateImage(
                        index: templateIndex,
                        row: row,
                        screenshotImages: rowImages,
                        localeCode: localization.localeCode,
                        localeState: appState.localeState,
                        availableFontFamilies: fontFamilies
                    )
                    guard let data = ExportService.encodeImage(image, format: .png) else {
                        throw AppStoreConnectUploadError.renderFailed(rowLabel: target.rowLabel, index: templateIndex)
                    }

                    let fileName = Self.fileName(row: row, index: templateIndex)
                    try await uploadOneScreenshot(setId: set.id, fileName: fileName, data: data)

                    completedSteps += 1
                    emit(label)
                }
            }
        }

        emit("Done")
    }

    private func uploadOneScreenshot(setId: String, fileName: String, data: Data) async throws {
        let reserved = try await api.reserveScreenshot(setId: setId, fileName: fileName, fileSize: data.count)
        let operations = reserved.attributes.uploadOperations ?? []
        for operation in operations {
            try Task.checkCancellation()
            try await api.uploadChunk(operation: operation, from: data)
        }
        try await api.commitScreenshot(id: reserved.id, md5Checksum: Self.md5Hex(data: data))
    }

    private static func fileName(row: ScreenshotRow, index: Int) -> String {
        let padded = String(format: "%02d", index + 1)
        let labelPart = row.label.isEmpty ? "screenshot" : row.label
        let sanitized = labelPart
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        return "\(padded)_\(sanitized).png"
    }

    private static func md5Hex(data: Data) -> String {
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum ASCLocaleMatcher {
    /// Prefix-match "en" → "en-US"/"en-GB". Exact match wins alone.
    static func matches(appCode: String, in localizations: [ASCAppStoreVersionLocalization]) -> [ASCAppStoreVersionLocalization] {
        let lower = appCode.lowercased()
        if let exact = localizations.first(where: { $0.attributes.locale.lowercased() == lower }) {
            return [exact]
        }
        let prefix = lower + "-"
        return localizations.filter { $0.attributes.locale.lowercased().hasPrefix(prefix) }
    }
}
