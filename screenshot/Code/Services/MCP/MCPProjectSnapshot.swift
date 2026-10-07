#if os(macOS)
import Foundation

struct MCPProjectListItem: Encodable {
    let id: String
    let name: String
    let isActive: Bool
    let isStarred: Bool
    let modifiedAt: String
}

struct MCPTemplateListItem: Encodable {
    let id: String
    let name: String
}

struct MCPLocaleSnapshot: Encodable {
    let code: String
    let label: String
    let isBase: Bool
    let isActive: Bool
}

struct MCPGradientStopSnapshot: Encodable {
    let color: String
    let location: Double
}

struct MCPGradientSnapshot: Encodable {
    let type: String
    let angle: Double
    let stops: [MCPGradientStopSnapshot]
    let centerX: Double
    let centerY: Double
}

struct MCPBackgroundSnapshot: Encodable {
    let style: String
    let color: String?
    let gradient: MCPGradientSnapshot?
    let imageFile: String?
    /// Per-language image files that replace `imageFile`, keyed by locale code; nil when none.
    var imageOverrides: [String: String]?
}

struct MCPShapeSnapshot: Encodable {
    let id: String
    let type: String
    let templateIndex: Int
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let rotation: Double
    let opacity: Double
    let color: String
    let borderRadius: Double?
    let text: String?
    let fontName: String?
    let fontSize: Double?
    let fontWeight: Int?
    let textAlign: String?
    /// Styled spans, present only when the text has per-range formatting.
    let textRuns: [MCPTextRun]?
    let translations: [String: String]?
    let translationTextRuns: [String: [MCPTextRun]]?
    /// Per-locale screenshot/image files, keyed by locale code. Without this a locale-targeted
    /// import leaves no trace in the row it returns — the base file is unchanged.
    let imageOverrides: [String: String]?
    let deviceCategory: String?
    let deviceFrameId: String?
    let screenshotFile: String?
    let imageFile: String?
    let starPoints: Int?
    let locked: Bool?
    let clipToTemplate: Bool?
    let shrinkToFit: Bool?
    /// Locales whose text loses lines in this box — what an agent should fix after translating.
    let textOverflowLocales: [String]?
}

struct MCPTemplateSnapshot: Encodable {
    let id: String
    let index: Int
    let overrideBackground: Bool
    let background: MCPBackgroundSnapshot?
}

struct MCPRowSnapshot: Encodable {
    let id: String
    let index: Int
    let label: String
    let width: Int
    let height: Int
    let spanBackground: Bool
    let showDevice: Bool
    let defaultDeviceCategory: String?
    let defaultDeviceFrameId: String?
    let variantId: String?
    let background: MCPBackgroundSnapshot
    let templates: [MCPTemplateSnapshot]
    let shapes: [MCPShapeSnapshot]
}

struct MCPProjectSnapshot: Encodable {
    let id: String
    let name: String
    let locales: [MCPLocaleSnapshot]
    let rows: [MCPRowSnapshot]
}

enum MCPSnapshotBuilder {
    /// Expects already-visible (non-tombstoned) projects, i.e. `state.visibleProjects`.
    static func projectList(_ projects: [Project], activeProjectId: UUID?) -> [MCPProjectListItem] {
        let dateFormatter = ISO8601DateFormatter()
        return projects.map { project in
            MCPProjectListItem(
                id: project.id.uuidString,
                name: project.name,
                isActive: project.id == activeProjectId,
                isStarred: project.isStarred,
                modifiedAt: dateFormatter.string(from: project.modifiedAt)
            )
        }
    }

    static func project(id: UUID, name: String, rows: [ScreenshotRow], localeState: LocaleState, availableFontFamilies: Set<String>) -> MCPProjectSnapshot {
        MCPProjectSnapshot(
            id: id.uuidString,
            name: name,
            locales: locales(localeState),
            rows: rows.enumerated().map { index, row in
                rowSnapshot(row, index: index, localeState: localeState, availableFontFamilies: availableFontFamilies)
            }
        )
    }

    static func locales(_ localeState: LocaleState) -> [MCPLocaleSnapshot] {
        localeState.locales.map { locale in
            MCPLocaleSnapshot(
                code: locale.code,
                label: locale.label,
                isBase: locale.code == localeState.baseLocaleCode,
                isActive: locale.code == localeState.activeLocaleCode
            )
        }
    }

    static func rowSnapshot(_ row: ScreenshotRow, index: Int, localeState: LocaleState, availableFontFamilies: Set<String>) -> MCPRowSnapshot {
        MCPRowSnapshot(
            id: row.id.uuidString,
            index: index,
            label: row.label,
            width: Int(row.templateWidth),
            height: Int(row.templateHeight),
            spanBackground: row.spanBackgroundAcrossRow,
            showDevice: row.showDevice,
            defaultDeviceCategory: row.defaultDeviceCategory?.rawValue,
            defaultDeviceFrameId: row.defaultDeviceFrameId,
            variantId: row.variantId?.uuidString,
            background: background(
                style: row.backgroundStyle,
                color: row.backgroundColorData,
                gradient: row.gradientConfig,
                imageConfig: row.backgroundImageConfig
            ),
            templates: row.templates.enumerated().map { templateIndex, template in
                MCPTemplateSnapshot(
                    id: template.id.uuidString,
                    index: templateIndex,
                    overrideBackground: template.overrideBackground,
                    background: template.overrideBackground
                        ? background(
                            style: template.backgroundStyle,
                            color: template.backgroundColor,
                            gradient: template.gradientConfig,
                            imageConfig: template.backgroundImageConfig
                        )
                        : nil
                )
            },
            shapes: row.shapes.map { shape in
                shapeSnapshot(shape, row: row, localeState: localeState, availableFontFamilies: availableFontFamilies)
            }
        )
    }

    static func shapeSnapshot(_ shape: CanvasShapeModel, row: ScreenshotRow, localeState: LocaleState, availableFontFamilies: Set<String>) -> MCPShapeSnapshot {
        var translations: [String: String] = [:]
        var translationRuns: [String: [MCPTextRun]] = [:]
        var imageOverrides: [String: String] = [:]
        for (localeCode, overrides) in localeState.overrides {
            if let override = overrides[shape.textTranslationKey] {
                if let text = override.text {
                    translations[localeCode] = text
                }
                if override.richText != nil {
                    translationRuns[localeCode] = MCPRichText.runs(
                        of: LocaleService.resolveShape(shape, localeCode: localeCode, localeState: localeState)
                    )
                }
            }
            if let file = overrides[shape.id.uuidString]?.overrideImageFileName {
                imageOverrides[localeCode] = file
            }
        }

        let overflowLocales = TextOverflowCheck.overflowingLocaleCodes(
            of: shape, localeState: localeState, availableFontFamilies: availableFontFamilies
        )

        return MCPShapeSnapshot(
            id: shape.id.uuidString,
            type: shape.type.rawValue,
            templateIndex: row.owningTemplateIndex(for: shape),
            x: shape.x,
            y: shape.y,
            width: shape.width,
            height: shape.height,
            rotation: shape.rotation,
            opacity: shape.opacity,
            color: shape.colorData.color.hexString,
            borderRadius: shape.borderRadius == 0 ? nil : shape.borderRadius,
            text: shape.text,
            fontName: shape.fontName,
            fontSize: shape.fontSize.map { Double($0) },
            fontWeight: shape.fontWeight,
            textAlign: shape.textAlign?.rawValue,
            textRuns: MCPRichText.runs(of: shape),
            translations: translations.isEmpty ? nil : translations,
            translationTextRuns: translationRuns.isEmpty ? nil : translationRuns,
            imageOverrides: imageOverrides.isEmpty ? nil : imageOverrides,
            deviceCategory: shape.deviceCategory?.rawValue,
            deviceFrameId: shape.deviceFrameId,
            screenshotFile: shape.screenshotFileName,
            imageFile: shape.imageFileName,
            starPoints: shape.starPointCount,
            locked: shape.isLocked,
            clipToTemplate: shape.clipToTemplate,
            shrinkToFit: shape.shrinkToFit,
            textOverflowLocales: overflowLocales.isEmpty ? nil : overflowLocales
        )
    }

    static func background(
        style: BackgroundStyle,
        color: CodableColor,
        gradient: GradientConfig,
        imageConfig: BackgroundImageConfig
    ) -> MCPBackgroundSnapshot {
        switch style {
        case .color:
            MCPBackgroundSnapshot(style: "color", color: color.color.hexString, gradient: nil, imageFile: nil)
        case .gradient:
            MCPBackgroundSnapshot(
                style: "gradient",
                color: nil,
                gradient: MCPGradientSnapshot(
                    type: gradient.gradientType.rawValue,
                    angle: gradient.angle,
                    stops: gradient.stops.map {
                        MCPGradientStopSnapshot(color: $0.colorData.color.hexString, location: $0.location)
                    },
                    centerX: gradient.centerX,
                    centerY: gradient.centerY
                ),
                imageFile: nil
            )
        case .image:
            MCPBackgroundSnapshot(
                style: "image",
                color: nil,
                gradient: nil,
                imageFile: imageConfig.fileName,
                imageOverrides: imageConfig.localeImages.isEmpty
                    ? nil
                    : imageConfig.localeImages.compactMapValues { $0.fileName ?? ($0.svgContent != nil ? "svg" : nil) }
            )
        }
    }
}
#endif
