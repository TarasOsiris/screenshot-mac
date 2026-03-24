import SwiftUI

extension AppState {

    // MARK: - Templates

    func addTemplate(to rowId: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == rowId }) else { return }
        registerUndoForRow(at: idx, "Add Template")
        appendTemplate(to: idx)
        scheduleSave()
    }

    /// Appends a new template (and its default device shape) to the row at the given index.
    /// Does not register undo or schedule save — callers handle that.
    func appendTemplate(to rowIndex: Int) {
        let color = Self.templateColors[rows[rowIndex].templates.count % Self.templateColors.count]
        rows[rowIndex].templates.append(ScreenshotTemplate(backgroundColor: color))
        let templateIndex = rows[rowIndex].templates.count - 1
        if let defaultCategory = rows[rowIndex].defaultDeviceCategory {
            var device = CanvasShapeModel.defaultDevice(
                centerX: rows[rowIndex].templateCenterX(at: templateIndex),
                centerY: rows[rowIndex].templateHeight / 2,
                templateHeight: rows[rowIndex].templateHeight,
                category: defaultCategory
            )
            if let frameId = rows[rowIndex].defaultDeviceFrameId, let frame = DeviceFrameCatalog.frame(for: frameId) {
                device.deviceCategory = frame.fallbackCategory
                device.deviceFrameId = frame.id
                device.adjustToDeviceAspectRatio(centerX: rows[rowIndex].templateCenterX(at: templateIndex))
            }
            rows[rowIndex].shapes.append(device)
        }
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
            if FileManager.default.fileExists(atPath: srcURL.path) {
                try? FileManager.default.copyItem(at: srcURL, to: dstURL)
                newTemplate.backgroundImageConfig.fileName = newBgFile
                screenshotImages[newBgFile] = screenshotImages[bgFileName]
            }
        }

        // Insert the new template right after the original
        rows[rowIndex].templates.insert(newTemplate, at: templateIndex + 1)

        // Duplicate shapes belonging to this template and shift to the new column
        let columnWidth = rows[rowIndex].templateWidth
        let sourceShapes = rows[rowIndex].shapes.filter {
            rows[rowIndex].owningTemplateIndex(for: $0) == templateIndex
        }

        // Shift existing shapes in templates after the insertion point to the right
        for i in rows[rowIndex].shapes.indices {
            let owner = rows[rowIndex].owningTemplateIndex(for: rows[rowIndex].shapes[i])
            if owner > templateIndex {
                rows[rowIndex].shapes[i].x += columnWidth
            }
        }

        // Create duplicated shapes for the new template
        var newShapes: [CanvasShapeModel] = []
        for shape in sourceShapes {
            var copy = shape.duplicated()
            copy.x += columnWidth
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
