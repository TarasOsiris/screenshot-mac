import Foundation
import MCP
@testable import Screenshot_Bro
import Testing

/// The guarantee this whole change exists for: a tool acts on the project its arguments name,
/// whatever the editor happens to have open.
///
/// The failure it prevents is not hypothetical — a plan built from one app's artwork and uploaded
/// to another app's listing. Both projects here have plausible iPhone rows, so no dimension check
/// would catch it; only the id does.
@Suite(.serialized)
@MainActor
struct MCPProjectBindingTests {

    private func decode(_ result: CallTool.Result) throws -> [String: Any] {
        guard case .text(let json, _, _) = result.content.first else {
            throw MCPToolError.failed("expected text content")
        }
        return try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    @Test func previewRendersTheNamedProjectNotTheOpenOne() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let credentials = AppStoreConnectCredentialsStore.shared
        let originalDemoMode = credentials.isDemoMode
        credentials.isDemoMode = true
        defer { credentials.isDemoMode = originalDemoMode }
        AppStoreConnectDemoData.shared.updateContext(localeCodes: [], rowSizes: [])

        let openProjectId = try #require(state.activeProject?.id)
        state.createProject(name: "Other App")
        let targetId = try #require(state.activeProject?.id)
        state.setASCAppId("demo-app-1", forProject: targetId)
        #expect(targetId != openProjectId)

        // Put the editor back on the *other* project, so a fallback to "active" would be wrong.
        state.selectProject(openProjectId)
        await state.projectOpenTask?.value
        #expect(state.activeProjectId == openProjectId)

        let executor = MCPToolExecutor(state: state, jobs: MCPJobStore())
        let result = await executor.call(
            name: "preview_app_store_screenshot_sync",
            arguments: ["project_id": .string(targetId.uuidString), "mode": .string("sync")]
        )
        #expect(result.isError != true, "unexpected error: \(result.content)")

        let envelope = try decode(result)
        let payload = try #require(envelope["result"] as? [String: Any])
        #expect(payload["project_id"] as? String == targetId.uuidString)
        #expect(payload["project_name"] as? String == "Other App")
        #expect(state.activeProjectId == openProjectId, "a read must not move the editor")
    }

    @Test func previewWithoutAProjectIdIsRejectedRatherThanGuessing() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let credentials = AppStoreConnectCredentialsStore.shared
        let originalDemoMode = credentials.isDemoMode
        credentials.isDemoMode = true
        defer { credentials.isDemoMode = originalDemoMode }

        let executor = MCPToolExecutor(state: state, jobs: MCPJobStore())
        let result = await executor.call(name: "preview_app_store_screenshot_sync", arguments: [:])
        #expect(result.isError == true, "an omitted project_id must fail, not fall back to the open project")
    }

    @Test func anUnknownProjectIdIsAClientError() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let credentials = AppStoreConnectCredentialsStore.shared
        let originalDemoMode = credentials.isDemoMode
        credentials.isDemoMode = true
        defer { credentials.isDemoMode = originalDemoMode }

        let executor = MCPToolExecutor(state: state, jobs: MCPJobStore())
        let result = await executor.call(
            name: "preview_app_store_screenshot_sync",
            arguments: ["project_id": .string(UUID().uuidString)]
        )
        #expect(result.isError == true)
    }

    /// A successful apply discards its plan, and the documented recovery is to reissue the
    /// identical call. Demanding a project_id at that point would break the one path that is
    /// guaranteed safe.
    @Test func applyWithNoPlanAndNoProjectIdResolvesToNoCheckout() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let executor = MCPToolExecutor(state: state, jobs: MCPJobStore())
        let checkout = try await executor.optionalCheckout(MCPArguments(nil), matching: nil)
        #expect(checkout == nil)
    }

    @Test func applyRejectsAProjectIdThatDisagreesWithThePlan() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let executor = MCPToolExecutor(state: state, jobs: MCPJobStore())
        let plan = ASCScreenshotSyncPlan(
            id: "plan-1",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(900),
            projectId: UUID(),
            projectModifiedAt: nil,
            appId: "123",
            sets: [],
            issues: [],
            directory: URL(fileURLWithPath: "/tmp")
        )
        await #expect(throws: MCPToolError.self) {
            _ = try await executor.optionalCheckout(
                MCPArguments(["project_id": .string(UUID().uuidString)]),
                matching: plan
            )
        }
    }

    /// A checkout of a project the editor does not have open must read that project's own rows.
    @Test func checkoutOfAClosedProjectReadsItsOwnRows() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }

        let firstId = try #require(state.activeProject?.id)
        let firstRowId = try #require(state.rows.first?.id)
        state.createProject(name: "Second")
        let secondId = try #require(state.activeProject?.id)
        state.addRow()
        state.saveAll()
        let secondRowIds = Set(state.rows.map(\.id))

        state.selectProject(firstId)
        await state.projectOpenTask?.value

        let checkout = try await ProjectCheckout.open(projectId: secondId, state: state)
        defer { checkout.dispose() }
        #expect(checkout.projectId == secondId)
        #expect(Set(checkout.rows.map(\.id)) == secondRowIds)
        #expect(!checkout.rows.contains { $0.id == firstRowId })
        #expect(state.activeProjectId == firstId, "opening a checkout must not move the editor")
    }
}
