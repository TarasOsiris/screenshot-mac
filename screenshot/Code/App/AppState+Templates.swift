import SwiftUI

extension AppState {

    // MARK: - Templates

    func addTemplate(to rowId: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == rowId }) else { return }
        registerUndoForRow(at: idx, "Add Template")
        appendTemplate(to: idx)
        scheduleSave()
    }

    func insertTemplateBefore(_ templateId: UUID, in rowId: UUID) {
        guard let rowIdx = rows.firstIndex(where: { $0.id == rowId }),
              let templateIndex = rows[rowIdx].templates.firstIndex(where: { $0.id == templateId }) else { return }
        registerUndoForRow(at: rowIdx, "Insert Screenshot Before")
        insertTemplate(inRowAt: rowIdx, at: templateIndex)
        scheduleSave()
    }

    func insertTemplateAfter(_ templateId: UUID, in rowId: UUID) {
        guard let rowIdx = rows.firstIndex(where: { $0.id == rowId }),
              let templateIndex = rows[rowIdx].templates.firstIndex(where: { $0.id == templateId }) else { return }
        registerUndoForRow(at: rowIdx, "Insert Screenshot After")
        insertTemplate(inRowAt: rowIdx, at: templateIndex + 1)
        scheduleSave()
    }

    /// Appends a new template (and its default device shape) to the row at the given index.
    /// Does not register undo or schedule save — callers handle that.
    func appendTemplate(to rowIndex: Int) {
        insertTemplate(inRowAt: rowIndex, at: rows[rowIndex].templates.count)
    }

    /// Inserts a new template at the given position, shifting existing shapes right.
    private func insertTemplate(inRowAt rowIndex: Int, at insertIndex: Int) {
        var row = rows[rowIndex]
        let columnWidth = row.templateWidth
        for i in row.shapes.indices {
            if row.owningTemplateIndex(for: row.shapes[i]) >= insertIndex {
                row.shapes[i].x += columnWidth
            }
        }
        let color = Self.templateColors[row.templates.count % Self.templateColors.count]
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
        rows[rowIndex] = row
    }

    func removeTemplate(_ templateId: UUID, from rowId: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == rowId }),
              let templateIndex = rows[idx].templates.firstIndex(where: { $0.id == templateId }) else { return }
        registerUndoForRow(at: idx, "Remove Template")
        let shapesToRemove = rows[idx].shapes.filter { rows[idx].owningTemplateIndex(for: $0) == templateIndex }
        let templateBgImage = rows[idx].templates[templateIndex].backgroundImageConfig.fileName
        let shapeImageCandidates = imageFileNames(for: shapesToRemove)
        for shape in shapesToRemove {
            LocaleService.removeShapeOverrides(&localeState, shapeId: shape.id)
        }
        let shapeIdsToRemove = Set(shapesToRemove.map(\.id))
        selectedShapeIds.subtract(shapeIdsToRemove)
        rows[idx].shapes.removeAll { shapeIdsToRemove.contains($0.id) }
        // Shift shapes from later templates left by one template width
        let tw = rows[idx].templateWidth
        for i in rows[idx].shapes.indices {
            if rows[idx].owningTemplateIndex(for: rows[idx].shapes[i]) > templateIndex {
                rows[idx].shapes[i].x -= tw
            }
        }
        rows[idx].templates.remove(at: templateIndex)
        // Cleanup orphaned images after removal (single-pass batch check)
        let allCandidates: [String?] = shapeImageCandidates + [templateBgImage]
        cleanupUnreferencedImages(allCandidates)
        scheduleSave()
    }

    func duplicateTemplate(_ templateId: UUID, in rowId: UUID) {
        duplicateTemplate(templateId, in: rowId, toEnd: false)
    }

    func duplicateTemplateToEnd(_ templateId: UUID, in rowId: UUID) {
        duplicateTemplate(templateId, in: rowId, toEnd: true)
    }

    private func duplicateTemplate(_ templateId: UUID, in rowId: UUID, toEnd: Bool) {
        guard let rowIndex = rows.firstIndex(where: { $0.id == rowId }),
              let templateIndex = rows[rowIndex].templates.firstIndex(where: { $0.id == templateId }) else { return }
        registerUndoForRow(at: rowIndex, "Duplicate Screenshot")
        let sourceTemplate = rows[rowIndex].templates[templateIndex]
        var newTemplate = sourceTemplate.duplicated()

        // Copy template background image if present
        if let bgFileName = sourceTemplate.backgroundImageConfig.fileName,
           let activeId = activeProjectId {
            let resourcesURL = PersistenceService.resourcesDir(activeId)
            let newBgFile = "\(newTemplate.id.uuidString)-bg.png"
            let srcURL = resourcesURL.appendingPathComponent(bgFileName)
            let dstURL = resourcesURL.appendingPathComponent(newBgFile)
            do {
                try FileManager.default.copyItem(at: srcURL, to: dstURL)
                newTemplate.backgroundImageConfig.fileName = newBgFile
                screenshotImages[newBgFile] = screenshotImages[bgFileName]
            } catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile {
                // Source background was already removed elsewhere; nothing to copy.
            } catch {
                saveError = String(localized: "Failed to copy template background: \(error.localizedDescription)")
            }
        }

        let insertIndex = toEnd ? rows[rowIndex].templates.count : templateIndex + 1
        rows[rowIndex].templates.insert(newTemplate, at: insertIndex)

        // Duplicate shapes belonging to this template and shift to the new column
        let columnWidth = rows[rowIndex].templateWidth
        let sourceShapes = rows[rowIndex].shapes.filter {
            rows[rowIndex].owningTemplateIndex(for: $0) == templateIndex
        }

        // Shift existing shapes in templates after the insertion point to the right
        for i in rows[rowIndex].shapes.indices {
            let owner = rows[rowIndex].owningTemplateIndex(for: rows[rowIndex].shapes[i])
            if owner >= insertIndex {
                rows[rowIndex].shapes[i].x += columnWidth
            }
        }

        // Create duplicated shapes for the new template
        let targetCenterX = rows[rowIndex].templateCenterX(at: insertIndex)
        let sourceCenterX = rows[rowIndex].templateCenterX(at: templateIndex)
        let shapeOffset = targetCenterX - sourceCenterX
        var newShapes: [CanvasShapeModel] = []
        for shape in sourceShapes {
            var copy = shape.duplicated()
            copy.x += shapeOffset
            LocaleService.copyShapeOverrides(&localeState, fromId: shape.id, toId: copy.id)
            copyImageFiles(for: &copy, originalId: shape.id)
            newShapes.append(copy)
        }
        rows[rowIndex].shapes.append(contentsOf: newShapes)

        scheduleSave()
    }

    func moveTemplateLeft(_ templateId: UUID, in rowId: UUID) {
        guard let rowIndex = rows.firstIndex(where: { $0.id == rowId }),
              let templateIndex = rows[rowIndex].templates.firstIndex(where: { $0.id == templateId }),
              templateIndex > 0 else { return }
        moveTemplate(inRowAt: rowIndex, from: templateIndex, to: templateIndex - 1, undoName: "Move Screenshot Left")
    }

    func moveTemplateRight(_ templateId: UUID, in rowId: UUID) {
        guard let rowIndex = rows.firstIndex(where: { $0.id == rowId }),
              let templateIndex = rows[rowIndex].templates.firstIndex(where: { $0.id == templateId }),
              templateIndex < rows[rowIndex].templates.count - 1 else { return }
        moveTemplate(inRowAt: rowIndex, from: templateIndex, to: templateIndex + 1, undoName: "Move Screenshot Right")
    }

    private func moveTemplate(inRowAt rowIndex: Int, from sourceIndex: Int, to destinationIndex: Int, undoName: String) {
        guard sourceIndex != destinationIndex else { return }

        var row = rows[rowIndex]
        guard row.templates.indices.contains(sourceIndex),
              row.templates.indices.contains(destinationIndex) else { return }

        registerUndoForRow(at: rowIndex, undoName)

        // Keep each shape visually attached to its screenshot column while columns are reordered.
        // Shapes that span multiple templates stay in place — they aren't tied to one column.
        let columnWidth = row.templateWidth
        let lo = min(sourceIndex, destinationIndex)
        let hi = max(sourceIndex, destinationIndex)
        let betweenShift = sourceIndex < destinationIndex ? -columnWidth : columnWidth
        for shapeIndex in row.shapes.indices {
            let shape = row.shapes[shapeIndex]

            // Shapes spanning multiple templates stay in place unless clipped to one template.
            if shape.clipToTemplate != true {
                let bb = shape.aabb
                let firstTemplate = max(0, Int(floor(bb.minX / columnWidth)))
                let lastTemplate = min(row.templates.count - 1, Int(floor((bb.maxX - 0.5) / columnWidth)))
                if firstTemplate != lastTemplate { continue }
            }

            let owner = row.owningTemplateIndex(for: shape)
            if owner == sourceIndex {
                row.shapes[shapeIndex].x += columnWidth * CGFloat(destinationIndex - sourceIndex)
            } else if owner >= lo && owner <= hi {
                row.shapes[shapeIndex].x += betweenShift
            }
        }

        let movedTemplate = row.templates.remove(at: sourceIndex)
        row.templates.insert(movedTemplate, at: destinationIndex)
        rows[rowIndex] = row
        scheduleSave()
    }
}
