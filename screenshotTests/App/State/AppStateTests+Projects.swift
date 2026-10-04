import AppKit
import CoreGraphics
@testable import Screenshot_Bro
import SwiftUI
import Testing

extension AppStateTests {
    // MARK: - Project operations

    @Test func createProjectSwitchesToNew() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let initialId = state.activeProjectId
        state.createProject(name: "New Project")
        #expect(state.projects.count == 2)
        #expect(state.activeProjectId != initialId)
        #expect(state.activeProject?.name == "New Project")
    }

    @Test func blankProjectCreationDismissesEditorPresentation() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.presentation.backgroundPopoverTemplateId = UUID()

        state.createProject(name: "New Project")

        #expect(state.presentation.backgroundPopoverTemplateId == nil)
    }

    @Test func projectSelectionDismissesEditorPresentation() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let originalProjectId = try #require(state.activeProjectId)
        state.createProject(name: "Second")
        state.presentation.backgroundPopoverTemplateId = UUID()

        state.selectProject(originalProjectId)

        #expect(state.presentation.backgroundPopoverTemplateId == nil)
    }

    @Test func projectDataReplacementDismissesEditorPresentation() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let projectId = try #require(state.activeProjectId)
        state.presentation.backgroundPopoverTemplateId = UUID()

        state.applyProjectData(ProjectData(rows: state.rows), for: projectId, origin: .open)

        #expect(state.presentation.backgroundPopoverTemplateId == nil)
    }

    @Test func projectSwitchCommitsActiveInlineTextEditBeforeSavingOldProject() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let originalProjectId = try #require(state.activeProjectId)
        let row = try #require(state.rows.first)
        state.addShape(
            CanvasShapeModel.defaultText(
                centerX: row.templateWidth / 2,
                centerY: row.templateHeight / 2
            )
        )
        let shape = try #require(state.rows.first?.shapes.first(where: { $0.type == .text }))

        state.textEdit.isActive = true
        state.textEdit.registerInlineTextCommit(for: shape.id) {
            var updated = shape
            updated.text = "Edited before switch"
            state.updateShape(updated)
        }

        state.createProject(name: "Second")

        let saved = try #require(PersistenceService.loadProject(originalProjectId))
        let savedShape = try #require(saved.rows.first?.shapes.first(where: { $0.id == shape.id }))
        #expect(savedShape.text == "Edited before switch")
    }

    @Test func duplicateProjectSwitchesToCopy() async throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let sourceId = try #require(state.activeProjectId)
        state.duplicateProject(sourceId)

        for _ in 0..<10 {
            if state.activeProject?.name.hasSuffix("Copy") == true {
                break
            }
            await Task.yield()
        }

        #expect(state.projects.count == 2)
        #expect(state.activeProject?.name.hasSuffix("Copy") == true)
    }

    @Test func renameProjectUpdatesName() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let projectId = try #require(state.activeProjectId)
        state.renameProject(projectId, to: "Renamed")
        #expect(state.activeProject?.name == "Renamed")
    }

    @Test func setProjectStarredTogglesFlagAndBumpsModifiedAt() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let projectId = try #require(state.activeProjectId)
        #expect(state.activeProject?.isStarred == false)
        let before = try #require(state.activeProject?.modifiedAt)

        state.setProjectStarred(projectId, true)
        #expect(state.activeProject?.isStarred == true)
        #expect(try #require(state.activeProject?.modifiedAt) >= before)

        state.setProjectStarred(projectId, false)
        #expect(state.activeProject?.isStarred == false)
    }

    @Test func deleteLastProjectLeavesEmptyState() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let projectId = state.activeProjectId!
        state.deleteProject(projectId)
        #expect(state.visibleProjects.isEmpty, "Deleting the last project should leave no project")
        #expect(state.activeProjectId == nil)
        #expect(state.rows.isEmpty)
    }

    /// A project created while another is still opening must not inherit that open's handle, or
    /// every save of the new project is skipped as "a load is in flight".
    @Test func creatingAProjectWhileAnotherIsOpeningStillSaves() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let first = try #require(state.activeProjectId)
        state.createProject(name: "Second")
        state.selectProject(first)
        #expect(state.projectOpenTask != nil)

        state.createProject(name: "Third")

        #expect(state.projectOpenTask == nil)
        let third = try #require(state.activeProjectId)
        #expect(PersistenceService.loadProject(third) != nil, "the new project was written")
    }

    /// The open project deleted on another device: the reload must switch properly, so the old
    /// rows are torn down rather than kept on screen (and saved) under the next project's id.
    @Test func aReloadThatFindsTheOpenProjectGoneSwitchesToAnother() async throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let doomed = try #require(state.activeProjectId)
        state.createProject(name: "Survivor")
        let survivor = try #require(state.activeProjectId)
        state.selectProject(doomed)
        await state.projectOpenTask?.value
        #expect(state.activeProjectId == doomed)

        var index = try #require(PersistenceService.loadIndex())
        let doomedIndex = try #require(index.projects.firstIndex { $0.id == doomed })
        index.projects[doomedIndex].markDeleted()
        try PersistenceService.saveIndex(index)
        state.reloadFromDisk()

        #expect(state.activeProjectId == survivor)
        #expect(state.projectOpenTask != nil, "a full switch, so saves wait for the survivor to load")
        await state.projectOpenTask?.value
        #expect(state.projectOpenTask == nil)
    }

    @Test func selectProjectClearsOpeningIndicatorAfterStructureThenStreamsImages() async throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let originalProjectId = try #require(state.activeProjectId)
        // Explicitly add an image shape so the test doesn't depend on makeDefaultRow
        // creating device shapes (which can fail when tests run concurrently and
        // the shared SCREENSHOT_DATA_DIR env var races).
        state.selectRow(state.rows.first?.id)
        let imageShape = CanvasShapeModel.defaultImage(centerX: 500, centerY: 500)
        state.addShape(imageShape)
        let firstShapeId = imageShape.id
        state.saveImage(makeTestImage(width: 1200, height: 2600), for: firstShapeId, source: .picker)
        state.saveAll()

        state.createProject(name: "Second")
        state.selectProject(originalProjectId)

        // The opening overlay is shown immediately while the project switches.
        #expect(state.isOpeningProject)

        // It clears as soon as the project *structure* (rows + locales) is applied,
        // WITHOUT waiting for images to finish downsampling — so the editor chrome
        // (locale bar, row controls) appears promptly even for projects with many
        // languages / large images.
        for _ in 0..<50 {
            if !state.isOpeningProject { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!state.isOpeningProject)

        // Images stream in afterwards, behind the already-visible UI, reporting a denominator.
        for _ in 0..<50 {
            if !state.screenshotImages.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!state.screenshotImages.isEmpty)

        // ...and the indicator clears itself once they have all landed.
        for _ in 0..<50 {
            if !state.projectOpen.isLoadingImages { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!state.projectOpen.isLoadingImages)

        // The phase announces how many it will load. Asserted where `beginImages` sets it —
        // synchronously, before the decode task can hop back to main — because sampling it from
        // the polling loops above is a race that a one-image project always loses.
        state.screenshotImages.removeAll()
        state.loadScreenshotImages()
        #expect(state.projectOpen.imagesTotal >= 1)
    }

    /// The editor's rows are kept out of the view tree until `.building`, so nothing may reveal
    /// them while `rows` still holds the outgoing project — that stale rebuild is what used to
    /// delay the loading overlay past the click.
    @Test func projectOpenRevealsRowsOnlyOnceTheIncomingProjectIsApplied() async throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let originalProjectId = try #require(state.activeProjectId)
        let originalRowId = try #require(state.rows.first?.id)
        state.createProject(name: "Second")
        state.selectProject(originalProjectId)

        #expect(state.projectOpen.phase == .preparing)
        #expect(!state.projectOpen.showsEditorContent)

        var sawStaleReveal = false
        for _ in 0..<100 {
            if state.projectOpen.showsEditorContent, state.rows.first?.id != originalRowId {
                sawStaleReveal = true
            }
            if !state.isOpeningProject { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(!sawStaleReveal, "rows were revealed before the incoming project was applied")
        #expect(state.projectOpen.phase == .idle)
        #expect(state.rows.first?.id == originalRowId)
    }

    /// `loadScreenshotImages` decodes in this order, so a large project must fill in from the
    /// top row down rather than in hash order.
    @Test func referencedImageWalkFollowsDocumentOrder() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        state.selectRow(state.rows.first?.id)
        for _ in 0..<2 {
            let shape = CanvasShapeModel.defaultImage(centerX: 500, centerY: 500)
            state.addShape(shape)
            state.saveImage(makeTestImage(width: 400, height: 800), for: shape.id, source: .picker)
        }
        state.addRow()
        state.selectRow(state.rows.last?.id)
        let lateShape = CanvasShapeModel.defaultImage(centerX: 500, centerY: 500)
        state.addShape(lateShape)
        state.saveImage(makeTestImage(width: 400, height: 800), for: lateShape.id, source: .picker)

        let ordered = state.editorReferencedImageFileNames()
        #expect(ordered.count == Set(ordered).count, "the walk must not repeat a file")

        let lastShape = try #require(state.rows.last?.shapes.last)
        #expect(lastShape.id == lateShape.id)
        let lateFile = try #require(lastShape.allImageFileNames.first)
        let lateIndex = try #require(ordered.firstIndex(of: lateFile))
        for early in state.rows[0].shapes.flatMap(\.allImageFileNames) {
            let earlyIndex = try #require(ordered.firstIndex(of: early))
            #expect(earlyIndex < lateIndex)
        }
    }

    /// Cold launch no longer loads the active project synchronously inside `AppState.init`;
    /// it goes through the same phased open a switch uses.
    @Test func coldLaunchLoadsTheActiveProjectThroughThePhasedOpen() async throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        state.selectRow(state.rows.first?.id)
        state.updateRowLabel(state.rows[0].id, text: "Cold Launch Row")
        state.saveAll()
        state.flushPendingSavesSynchronously()

        let relaunched = AppState()
        for _ in 0..<200 {
            if !relaunched.isOpeningProject, !relaunched.rows.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(relaunched.hasCompletedInitialLoad)
        #expect(relaunched.activeProjectId == state.activeProjectId)
        #expect(relaunched.rows.first?.label == "Cold Launch Row")
    }

    func makeDevice(in row: ScreenshotRow, templateIndex: Int, frame: DeviceFrame) -> CanvasShapeModel {
        let centerX = row.templateCenterX(at: templateIndex)
        let centerY = row.templateHeight / 2
        var device = CanvasShapeModel.defaultDevice(
            centerX: centerX,
            centerY: centerY,
            templateHeight: row.templateHeight,
            category: frame.fallbackCategory
        )
        device.selectRealFrame(frame)
        device.adjustToDeviceAspectRatio(centerX: centerX)
        return device
    }
}
