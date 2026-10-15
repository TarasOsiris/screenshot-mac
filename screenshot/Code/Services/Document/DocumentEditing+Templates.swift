import Foundation

extension DocumentEditing {

    // MARK: - Templates

    /// Inserts a new template at `insertIndex`, shifting later shapes right and adding the row's default device.
    static func insertTemplate(in row: inout ScreenshotRow, at insertIndex: Int) {
        let columnWidth = row.templateWidth
        for i in row.shapes.indices where row.owningTemplateIndex(for: row.shapes[i]) >= insertIndex {
            row.shapes[i].x += columnWidth
        }
        let color = ScreenshotRow.templateColors[row.templates.count % ScreenshotRow.templateColors.count]
        row.templates.insert(ScreenshotTemplate(backgroundColor: color), at: insertIndex)
        if let defaultCategory = row.defaultDeviceCategory {
            var device = CanvasShapeModel.defaultDevice(
                centerX: row.templateCenterX(at: insertIndex),
                centerY: row.templateHeight / 2,
                templateHeight: row.templateHeight,
                category: defaultCategory
            )
            if let frameId = row.defaultDeviceFrameId, let frame = DeviceFrameCatalog.frame(for: frameId) {
                device.deviceCategory = frame.fallbackCategory
                device.deviceFrameId = frame.id
                device.adjustToDeviceAspectRatio(centerX: row.templateCenterX(at: insertIndex))
            }
            row.shapes.append(device)
        }
    }

    /// Removes the template and the shapes contained in it; spanning shapes survive so their visible
    /// portion on neighboring templates is preserved.
    static func removeTemplate(
        at templateIndex: Int,
        fromRowAt rowIndex: Int,
        rows: inout [ScreenshotRow],
        localeState: inout LocaleState
    ) -> (removedShapeIds: Set<UUID>, imageCandidates: [String?]) {
        let shapesToRemove = rows[rowIndex].shapesContained(inTemplateAt: templateIndex)
        var imageCandidates: [String?] = imageFileNames(for: shapesToRemove, localeState: localeState)
        imageCandidates += rows[rowIndex].templates[templateIndex].backgroundImageConfig.allImageFileNames
        for shape in shapesToRemove {
            LocaleService.removeShapeOverrides(&localeState, shapeId: shape.id)
        }
        let removedIds = Set(shapesToRemove.map(\.id))
        rows[rowIndex].shapes.removeAll { removedIds.contains($0.id) }
        let width = rows[rowIndex].templateWidth
        for i in rows[rowIndex].shapes.indices where rows[rowIndex].owningTemplateIndex(for: rows[rowIndex].shapes[i]) > templateIndex {
            rows[rowIndex].shapes[i].x -= width
        }
        rows[rowIndex].templates.remove(at: templateIndex)
        cleanupOrphanedTranslationOverrides(rows: rows, localeState: &localeState)
        return (removedIds, imageCandidates)
    }

    /// Moves a template, keeping each single-column shape attached to its screenshot. Spanning shapes stay put.
    static func moveTemplate(in row: inout ScreenshotRow, from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              row.templates.indices.contains(sourceIndex),
              row.templates.indices.contains(destinationIndex) else { return }
        let columnWidth = row.templateWidth
        let lo = min(sourceIndex, destinationIndex)
        let hi = max(sourceIndex, destinationIndex)
        let betweenShift = sourceIndex < destinationIndex ? -columnWidth : columnWidth
        for shapeIndex in row.shapes.indices {
            let shape = row.shapes[shapeIndex]
            if row.spansMultipleTemplates(shape) { continue }

            let owner = row.owningTemplateIndex(for: shape)
            if owner == sourceIndex {
                row.shapes[shapeIndex].x += columnWidth * CGFloat(destinationIndex - sourceIndex)
            } else if owner >= lo && owner <= hi {
                row.shapes[shapeIndex].x += betweenShift
            }
        }
        let movedTemplate = row.templates.remove(at: sourceIndex)
        row.templates.insert(movedTemplate, at: destinationIndex)
    }

    /// Copies the template and the shapes it owns to `insertIndex`, shifting later columns right.
    static func duplicateTemplate(
        at templateIndex: Int,
        to insertIndex: Int,
        in row: inout ScreenshotRow,
        localeState: inout LocaleState,
        resources: ImageResourceCopying
    ) {
        let sourceTemplate = row.templates[templateIndex]
        var newTemplate = sourceTemplate.duplicated()
        if let bgFileName = sourceTemplate.backgroundImageConfig.fileName {
            let newBgFile = "\(newTemplate.id.uuidString)-bg.png"
            if resources.copyImageResource(bgFileName, to: newBgFile) {
                newTemplate.backgroundImageConfig.fileName = newBgFile
            }
        }
        row.templates.insert(newTemplate, at: insertIndex)

        let columnWidth = row.templateWidth
        let sourceShapes = row.shapes.filter { row.owningTemplateIndex(for: $0) == templateIndex }
        for i in row.shapes.indices where row.owningTemplateIndex(for: row.shapes[i]) >= insertIndex {
            row.shapes[i].x += columnWidth
        }

        let shapeOffset = row.templateCenterX(at: insertIndex) - row.templateCenterX(at: templateIndex)
        for shape in sourceShapes {
            var copy = shape.duplicated()
            copy.x += shapeOffset
            LocaleService.copyShapeOverrides(&localeState, fromId: shape.id, toId: copy.id)
            copyImageFiles(for: &copy, originalId: shape.id, localeState: &localeState, resources: resources)
            row.shapes.append(copy)
        }
    }
}
