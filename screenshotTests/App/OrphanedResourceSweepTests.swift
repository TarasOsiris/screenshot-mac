import AppKit
@testable import Screenshot_Bro
import Testing

/// The sweep that reclaims unreferenced resources is the one piece of the app that deletes user
/// data on its own, and it used to classify iCloud's `.<name>.icloud` placeholders as orphans —
/// which deletes the item itself, on every device, for a project that simply hadn't finished
/// downloading. These pin the allowlist that replaced it.
@Suite(.serialized)
@MainActor
struct OrphanedResourceSweepTests {

    private func urls(_ names: [String]) -> [URL] {
        let base = URL(fileURLWithPath: "/tmp/resources", isDirectory: true)
        return names.map { base.appendingPathComponent($0) }
    }

    private func orphanNames(_ names: [String], referenced: Set<String>) -> [String] {
        AppState.orphanedResourceURLs(in: urls(names), referenced: referenced).map(\.lastPathComponent)
    }

    @Test func unreferencedImageIsAnOrphan() {
        #expect(orphanNames(["a.png", "b.png"], referenced: ["a.png"]) == ["b.png"])
    }

    @Test func placeholderForAReferencedImageIsSpared() {
        #expect(orphanNames([".a.png.icloud"], referenced: ["a.png"]).isEmpty)
    }

    /// Also spared when nothing references it: deleting a placeholder deletes the item, and the
    /// document that would reference it may itself still be downloading.
    @Test func placeholderForAnUnreferencedImageIsSpared() {
        #expect(orphanNames([".gone.png.icloud"], referenced: []).isEmpty)
    }

    @Test func fontsAndUnknownFilesAreSpared() {
        let names = ["DMSans.ttf", "Playfair.otf", "family.ttc", ".DS_Store", "notes.txt", "sub"]
        #expect(orphanNames(names, referenced: []).isEmpty)
    }

    @Test func uppercaseExtensionStillCounts() {
        #expect(orphanNames(["A.PNG"], referenced: []) == ["A.PNG"])
    }

    @Test func resourceStatePrefersDownloadingOverMissing() {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }

        #expect(CanvasResourceState(nil, in: state) == .satisfied)
        #expect(CanvasResourceState("here.png", in: state) == .satisfied)

        state.missingImageFileNames = ["gone.png", "both.png"]
        state.pendingDownloadImageFileNames = ["later.png", "both.png"]

        #expect(CanvasResourceState("gone.png", in: state) == .missing)
        #expect(CanvasResourceState("later.png", in: state) == .downloading)
        #expect(CanvasResourceState("both.png", in: state) == .downloading)
    }

    /// A peer's `project.json` can be newer by mtime and behind in content, so the document an
    /// iCloud reload swaps in is not a licence to delete what this device just wrote.
    @Test func remoteReloadLeavesTheResourcesDirectoryAlone() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let projectId = try #require(state.activeProjectId)
        let stray = try seedResource(named: "stray.png", in: projectId)

        state.applyProjectData(ProjectData(rows: state.rows), for: projectId, origin: .remoteReload)
        try await Task.sleep(for: .milliseconds(300))

        #expect(FileManager.default.fileExists(atPath: stray.path))
    }

    @Test func openSweepsUnreferencedResources() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let projectId = try #require(state.activeProjectId)
        let stray = try seedResource(named: "stray.png", in: projectId)
        let placeholder = try seedResource(named: ".pending.png.icloud", in: projectId)

        state.applyProjectData(ProjectData(rows: state.rows), for: projectId, origin: .open)

        let fm = FileManager.default
        for _ in 0..<40 where fm.fileExists(atPath: stray.path) {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!fm.fileExists(atPath: stray.path))
        #expect(fm.fileExists(atPath: placeholder.path))
    }

    /// A referenced file that isn't on disk used to reach nothing at all: no log, no report, no
    /// UI — the frame just drew empty, which is indistinguishable from a design choice.
    @Test func absentResourceIsRecordedAsMissing() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let projectId = try #require(state.activeProjectId)
        _ = try seedImageResource(named: "keep.png", in: projectId)
        state.rows[0].backgroundImageConfig.fileName = "keep.png"
        state.rows[0].backgroundStyle = .image
        state.rows[0].templates[0].backgroundImageConfig.fileName = "gone.png"
        state.rows[0].templates[0].backgroundStyle = .image
        state.rows[0].templates[0].overrideBackground = true

        state.loadScreenshotImages()
        for _ in 0..<40 where state.missingImageFileNames.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(state.missingImageFileNames == ["gone.png"])
        #expect(state.pendingDownloadImageFileNames.isEmpty)
        #expect(CanvasResourceState("gone.png", in: state) == .missing)
    }

    /// A placeholder means the bytes are coming, so it must not be reported as a hole.
    @Test func placeholderResourceIsRecordedAsPendingNotMissing() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let projectId = try #require(state.activeProjectId)
        _ = try seedResource(named: ".later.png.icloud", in: projectId)
        state.rows[0].backgroundImageConfig.fileName = "later.png"
        state.rows[0].backgroundStyle = .image

        state.loadScreenshotImages()
        for _ in 0..<40 where state.pendingDownloadImageFileNames.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(state.pendingDownloadImageFileNames == ["later.png"])
        #expect(state.missingImageFileNames.isEmpty)
        #expect(CanvasResourceState("later.png", in: state) == .downloading)
    }

    /// The retry is the other half of not deleting placeholders: without it the canvas stays empty
    /// until the project is reopened, because nothing re-reads a resource after the open.
    @Test func aResourceThatFinishesDownloadingClearsItsPendingState() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let projectId = try #require(state.activeProjectId)
        let placeholder = try seedResource(named: ".later.png.icloud", in: projectId)
        state.rows[0].backgroundImageConfig.fileName = "later.png"
        state.rows[0].backgroundStyle = .image

        state.loadScreenshotImages()
        for _ in 0..<40 where state.pendingDownloadImageFileNames.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(state.pendingDownloadImageFileNames == ["later.png"])

        try FileManager.default.removeItem(at: placeholder)
        try seedImageResource(named: "later.png", in: projectId)
        state.reloadPendingScreenshotImages()
        for _ in 0..<40 where state.screenshotImages["later.png"] == nil {
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(state.screenshotImages["later.png"] != nil)
        #expect(state.pendingDownloadImageFileNames.isEmpty)
        #expect(CanvasResourceState("later.png", in: state) == .satisfied)
    }

    @discardableResult
    private func seedResource(named name: String, in projectId: UUID, contents: Data = Data([0])) throws -> URL {
        let dir = PersistenceService.resourcesDir(projectId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }

    /// Real PNG bytes: the loader treats a file it cannot decode as a hole, which is correct and
    /// would make a placeholder-shaped fixture pass for the wrong reason.
    @discardableResult
    private func seedImageResource(named name: String, in projectId: UUID) throws -> URL {
        let data = try #require(ExportService.pngData(from: makeSolidImage(.systemBlue, width: 4, height: 4)))
        return try seedResource(named: name, in: projectId, contents: data)
    }
}

@Suite(.serialized)
struct UbiquitousPlaceholderTests {

    @Test func placeholderURLIsTheHiddenSibling() {
        let url = URL(fileURLWithPath: "/tmp/resources/shot.png")
        #expect(PersistenceService.ubiquitousPlaceholderURL(for: url).lastPathComponent == ".shot.png.icloud")
    }

    @Test func recognisesPlaceholderNames() {
        #expect(PersistenceService.isUbiquitousPlaceholder(".shot.png.icloud"))
        #expect(!PersistenceService.isUbiquitousPlaceholder("shot.png"))
        #expect(!PersistenceService.isUbiquitousPlaceholder("shot.icloud"))
    }

    @Test func availabilityTellsAWaitApartFromAHole() throws {
        let dir = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let present = dir.appendingPathComponent("here.png")
        try Data([0]).write(to: present)
        #expect(PersistenceService.availability(of: present) == .present)

        let pending = dir.appendingPathComponent("later.png")
        try Data().write(to: PersistenceService.ubiquitousPlaceholderURL(for: pending))
        #expect(PersistenceService.availability(of: pending) == .notDownloaded)

        #expect(PersistenceService.availability(of: dir.appendingPathComponent("nowhere.png")) == .absent)
    }
}
