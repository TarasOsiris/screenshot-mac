import Foundation
import MCP
@testable import Screenshot_Bro
import Testing

/// The tool list, its schemas, the editing set and the handlers are written in separate places;
/// these pin that they describe the same tools.
@Suite(.serialized)
@MainActor
struct MCPToolCatalogTests {

    private struct NoCopy: ImageResourceCopying {
        func copyImageResource(_ fileName: String, to newFileName: String) -> Bool { false }
    }

    private func declaresProjectId(_ tool: MCPToolName) -> Bool {
        MCPToolCatalog.inputSchema(for: tool)?.schemaProperties?["project_id"] != nil
    }

    @Test func everyToolHasASchema() {
        for tool in MCPToolName.allCases {
            #expect(MCPToolCatalog.inputSchema(for: tool) != nil, "\(tool.rawValue) has no input schema")
        }
    }

    /// `project_id` is how a client reaches a closed project; an editing tool without it can only
    /// edit the open one, and a non-editing tool declaring it would never be checked out.
    @Test func editingToolsAreExactlyTheOnesTakingAProjectId() {
        let projectScoped: Set<MCPToolName> = [
            // Read or act on a whole project rather than editing its document.
            .getProject, .renameProject, .deleteProject, .switchProject, .exportProject, .renderPreview,
            .listVariants, .listCatalog, .undo, .redo, .linkProjectStores, .previewAppStoreScreenshotSync,
            .applyAppStoreScreenshotSync, .previewPlayUpload, .uploadPlayScreenshots, .getAppStoreMetadata,
            .updateAppStoreDescription, .updateAppStoreMetadata,
            // Edit, but as their own transaction around `applyEdit`.
            .batch, .setTranslations,
        ]
        for tool in MCPToolName.allCases where tool.isEditing {
            #expect(declaresProjectId(tool), "\(tool.rawValue) edits but does not take project_id")
        }
        for tool in MCPToolName.allCases where !tool.isEditing && declaresProjectId(tool) {
            #expect(projectScoped.contains(tool), "\(tool.rawValue) takes project_id but is not an editing tool")
        }
    }

    @Test func everyAvailableToolHasAHandler() {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let executor = MCPToolExecutor(state: state)
        for tool in MCPToolName.available {
            #expect(executor.handler(for: tool) != nil, "\(tool.rawValue) is not dispatched")
        }
    }

    /// Empty arguments make most edits throw — anything but `unknownTool` proves `applyEdit` routes it.
    @Test func everyEditingToolIsApplied() {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let executor = MCPToolExecutor(state: state)
        for tool in MCPToolName.allCases where tool.isEditing {
            var document = state.document
            var context = MCPEditContext(availableFontFamilies: [], resources: NoCopy())
            do {
                _ = try executor.applyEdit(
                    tool, MCPArguments([:], schema: MCPToolCatalog.inputSchema(for: tool)),
                    to: &document, context: &context
                )
            } catch MCPToolError.unknownTool {
                Issue.record("\(tool.rawValue) is editing but applyEdit does not handle it")
            } catch {}
        }
    }
}
