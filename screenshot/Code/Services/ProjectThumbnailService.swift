import SwiftUI

/// Renders a small snapshot of a project's first row for use as a card thumbnail.
/// Loads the project's data straight from disk (the project need not be active), renders
/// through the shared export path so the thumbnail matches the editor, then downsamples.
/// Results are cached per project + `modifiedAt`, so a render only happens once per edit.
@MainActor
enum ProjectThumbnailService {
    private struct Key: Hashable {
        let id: UUID
        let modifiedAt: Date
    }

    private static let maxDimension: CGFloat = 600
    private static var cache: [Key: Image] = [:]

    static func thumbnail(for project: Project) -> Image? {
        let key = Key(id: project.id, modifiedAt: project.modifiedAt)
        if let cached = cache[key] { return cached }

        guard let data = PersistenceService.loadProject(project.id),
              let row = data.rows.first(where: { !$0.templates.isEmpty }) ?? data.rows.first,
              !row.templates.isEmpty
        else { return nil }

        let localeState = data.localeState ?? .default
        let localeCode = localeState.activeLocaleCode
        let images = loadImages(
            fileNames: referencedFileNames(row: row, localeState: localeState, localeCode: localeCode),
            projectId: project.id
        )

        let full = ExportService.renderRowImage(
            row: row,
            screenshotImages: images,
            localeCode: localeCode,
            localeState: localeState
        )
        let small = full.tiffRepresentation
            .flatMap { AppState.downsampledImage(from: $0, maxDimension: maxDimension) } ?? full

        let image = Image(nsImage: small)
        // Drop any older snapshot for this project so the cache doesn't grow per edit.
        cache = cache.filter { $0.key.id != project.id }
        cache[key] = image
        return image
    }

    private static func referencedFileNames(row: ScreenshotRow, localeState: LocaleState, localeCode: String) -> Set<String> {
        var result = Set<String>()
        if let f = row.backgroundImageConfig.fileName { result.insert(f) }
        for template in row.templates {
            if let f = template.backgroundImageConfig.fileName { result.insert(f) }
        }
        for shape in row.shapes {
            for f in shape.allImageFileNames { result.insert(f) }
        }
        if let overrides = localeState.overrides[localeCode] {
            for override in overrides.values {
                if let f = override.overrideImageFileName { result.insert(f) }
            }
        }
        return result
    }

    private static func loadImages(fileNames: Set<String>, projectId: UUID) -> [String: NSImage] {
        let dir = PersistenceService.resourcesDir(projectId)
        var images: [String: NSImage] = [:]
        for name in fileNames {
            if let image = NSImage(contentsOf: dir.appendingPathComponent(name)) {
                images[name] = image
            }
        }
        return images
    }
}
