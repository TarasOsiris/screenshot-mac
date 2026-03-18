import Testing
import Foundation
import SwiftUI
@testable import Screenshot_Bro

struct ICloudSyncServiceTests {

    @Test func sourceProjectVersionWinsUsesProjectPayloadTimestamp() throws {
        let sourceRoot = makeTemporaryDataDirectory(label: "icloud-sync-source")
        let destinationRoot = makeTemporaryDataDirectory(label: "icloud-sync-destination")
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: destinationRoot)
        }

        let projectId = UUID()
        var sourceProject = Project(id: projectId, name: "Shared Project")
        var destinationProject = Project(id: projectId, name: "Shared Project")
        sourceProject.modifiedAt = Date(timeIntervalSince1970: 10)
        destinationProject.modifiedAt = Date(timeIntervalSince1970: 20)

        var sourceData = ProjectData(
            rows: [ScreenshotRow(label: "Source", templates: [ScreenshotTemplate(backgroundColor: .blue)])],
            localeState: .default
        )
        var destinationData = ProjectData(
            rows: [ScreenshotRow(label: "Destination", templates: [ScreenshotTemplate(backgroundColor: .green)])],
            localeState: .default
        )
        sourceData.modifiedAt = Date(timeIntervalSince1970: 30)
        destinationData.modifiedAt = Date(timeIntervalSince1970: 15)

        PersistenceService.ensureDirectories(at: sourceRoot)
        PersistenceService.ensureDirectories(at: destinationRoot)
        try PersistenceService.saveIndex(ProjectIndex(projects: [sourceProject], activeProjectId: projectId), at: sourceRoot)
        try PersistenceService.saveIndex(ProjectIndex(projects: [destinationProject], activeProjectId: projectId), at: destinationRoot)
        try PersistenceService.saveProject(projectId, data: sourceData, at: sourceRoot)
        try PersistenceService.saveProject(projectId, data: destinationData, at: destinationRoot)

        let sourceWins = ICloudSyncService.sourceProjectVersionWins(
            projectId,
            sourceProjects: [projectId: sourceProject],
            destinationProjects: [projectId: destinationProject],
            sourceRoot: sourceRoot,
            destinationRoot: destinationRoot
        )

        #expect(sourceWins)
    }
}
