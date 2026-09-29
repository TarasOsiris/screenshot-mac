import Foundation
import ImageIO

/// Which screenshots in a folder go to which project locale.
struct LocaleFolderImportPlan: Equatable {
    struct LocaleBatch: Equatable {
        let localeCode: String
        var files: [URL]
    }

    /// In project-locale order, base locale first.
    var batches: [LocaleBatch] = []
    /// Folder names that read as locale codes but match no project locale — including a second
    /// regional folder (`en-GB` beside `en-US`) for a project locale another folder already fills.
    var unmatchedLocaleFolders: [String] = []
    /// Images whose pixel size isn't the row's, e.g. the other devices in a fastlane folder.
    var skippedForSize: [URL] = []

    var imageCount: Int { batches.reduce(0) { $0 + $1.files.count } }
}

/// Reads a folder laid out per locale — `en-US/01.png` (fastlane `deliver`),
/// `en-US/images/phoneScreenshots/1.png` (fastlane `supply`), or flat `01_de.png` names.
enum LocaleFolderImportPlanner {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "webp", "tif", "tiff"]

    static func plan(
        folder: URL,
        projectLocaleCodes: [String],
        rowSize: CGSize,
        fileManager: FileManager = .default,
        pixelSize: (URL) -> CGSize? = { LocaleFolderImportPlanner.pixelSize(of: $0) }
    ) -> LocaleFolderImportPlan {
        var filesByLocale: [String: [URL]] = [:]
        var unmatched: [String] = []
        var skipped: [URL] = []

        func accept(_ file: URL, for localeCode: String) {
            guard let size = pixelSize(file), matches(size, rowSize) else {
                skipped.append(file)
                return
            }
            filesByLocale[localeCode, default: []].append(file)
        }

        let children = (try? fileManager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []

        var foldersByLocale: [String: [URL]] = [:]
        for child in children.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let name = child.lastPathComponent
            if isDirectory(child) {
                if let code = LocaleCodeMatcher.match(name, among: projectLocaleCodes) {
                    foldersByLocale[code, default: []].append(child)
                } else if LocaleCodeMatcher.looksLikeLocaleCode(name) {
                    unmatched.append(name)
                }
            } else if isImage(child), let code = localeCode(inFileName: name, among: projectLocaleCodes) {
                accept(child, for: code)
            }
        }
        // One folder per project locale: `en-US`, `en-GB` and `en-AU` all prefix-match `en`, and
        // importing all three would stack three sets of screenshots into one row.
        for (code, folders) in foldersByLocale {
            let chosen = preferredFolder(folders, for: code)
            for file in imageFiles(under: chosen, fileManager: fileManager) {
                accept(file, for: code)
            }
            unmatched += folders.filter { $0 != chosen }.map(\.lastPathComponent)
        }
        unmatched.sort { $0.localizedStandardCompare($1) == .orderedAscending }

        let batches = projectLocaleCodes.compactMap { code -> LocaleFolderImportPlan.LocaleBatch? in
            guard let files = filesByLocale[code], !files.isEmpty else { return nil }
            return .init(localeCode: code, files: files)
        }
        return LocaleFolderImportPlan(batches: batches, unmatchedLocaleFolders: unmatched, skippedForSize: skipped)
    }

    /// An exact name first, then the App Store's own code for the language (`en` → `en-US`), then
    /// the first in Finder order.
    private static func preferredFolder(_ folders: [URL], for projectCode: String) -> URL {
        let names = folders.map { $0.lastPathComponent.replacingOccurrences(of: "_", with: "-").lowercased() }
        if let exact = names.firstIndex(of: projectCode.lowercased()) { return folders[exact] }
        if let storeCode = ASCLanguageMatcher.appStoreLanguageCode(forProjectCode: projectCode)?.lowercased(),
           let store = names.firstIndex(of: storeCode) {
            return folders[store]
        }
        return folders[0]
    }

    /// The bundled language a folder like `fr-FR` or `zh-Hans` stands for, so the import can offer
    /// to add it to the project.
    static func presetLocale(forFolderName name: String) -> LocaleDefinition? {
        let presets = LocalePresets.all
        guard let code = LocaleCodeMatcher.match(name, among: presets.map(\.code)) else { return nil }
        return presets.first { $0.code == code }
    }

    /// The first `_`/space/`.`-separated token of the name that matches a project locale.
    /// Hyphens stay inside tokens so `en-US` survives as one.
    static func localeCode(inFileName name: String, among projectCodes: [String]) -> String? {
        let stem = (name as NSString).deletingPathExtension
        let tokens = stem.split(whereSeparator: { $0 == "_" || $0 == " " || $0 == "." }).map(String.init)
        for token in tokens where LocaleCodeMatcher.looksLikeLocaleCode(token) {
            if let code = LocaleCodeMatcher.match(token, among: projectCodes) { return code }
        }
        return nil
    }

    /// Sorted by path relative to the locale folder, in Finder order, so `2.png` precedes `10.png`.
    private static func imageFiles(under folder: URL, fileManager: FileManager) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        let basePath = folder.standardizedFileURL.path
        return enumerator.compactMap { $0 as? URL }
            .filter { !isDirectory($0) && isImage($0) }
            .map { (url: $0, relative: String($0.standardizedFileURL.path.dropFirst(basePath.count))) }
            .sorted { $0.relative.localizedStandardCompare($1.relative) == .orderedAscending }
            .map(\.url)
    }

    private static func isImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// One pixel of slack: some tools round odd simulator sizes.
    private static func matches(_ size: CGSize, _ rowSize: CGSize) -> Bool {
        abs(size.width - rowSize.width) <= 1 && abs(size.height - rowSize.height) <= 1
    }

    /// Reads the header only — decoding every screenshot in a fastlane folder just to learn its
    /// size would cost seconds.
    static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        // EXIF orientations 5–8 are rotated a quarter turn; the imported image is upright.
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }
}
