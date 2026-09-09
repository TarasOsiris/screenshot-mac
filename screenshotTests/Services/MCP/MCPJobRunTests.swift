import Foundation
import MCP
@testable import Screenshot_Bro
import Testing

@Suite(.serialized)
@MainActor
struct MCPJobRunTests {

    private func decode(_ result: CallTool.Result) throws -> [String: Any] {
        guard case .text(let json, _, _) = result.content.first else {
            throw MCPToolError.failed("expected text content")
        }
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try #require(object as? [String: Any])
    }

    private func phase(_ result: CallTool.Result) throws -> String {
        try #require(try decode(result)["phase"] as? String)
    }

    /// The regression pin for the whole feature: a large request must hand back a job id long
    /// before the work is done, so the client's timeout stops being the operation's deadline.
    @Test func asyncJobReturnsBeforeItsBodyFinishes() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let store = MCPJobStore()
        let executor = MCPToolExecutor(state: state, jobs: store)

        let result = try await executor.runJob(kind: .preview, totalUnits: 4, mode: .async) { handle in
            handle.phase(.rendering)
            try await Task.sleep(for: .milliseconds(400))
            handle.progress(completed: 4)
            return MCPJobOutcome(.object(["done": .bool(true)]))
        }

        let jobId = try #require(try decode(result)["job_id"] as? String)
        #expect(try phase(result) != MCPJobPhase.succeeded.rawValue, "async must not wait for the body")

        var settled: String?
        for _ in 0..<100 {
            let status = try executor.jobStatusResult(jobId)
            let current = try phase(status)
            if current == MCPJobPhase.succeeded.rawValue { settled = current; break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(settled == MCPJobPhase.succeeded.rawValue, "the job must reach a terminal phase on its own")
        #expect(store.job(jobId)?.result != nil, "the terminal payload is retained for a client that timed out")
    }

    @Test func syncJobReturnsTheTerminalEnvelopeDirectly() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let executor = MCPToolExecutor(state: state, jobs: MCPJobStore())

        let result = try await executor.runJob(kind: .preview, totalUnits: 1, mode: .sync) { handle in
            handle.progress(completed: 1)
            return MCPJobOutcome(.object(["done": .bool(true)]))
        }
        #expect(try phase(result) == MCPJobPhase.succeeded.rawValue)
        #expect(try decode(result)["result"] != nil, "the payload rides inside the same envelope")
    }

    /// `apply` reports a partial failure by *returning*, not throwing. A job that treated "the
    /// body returned" as success reported `succeeded` on an upload that left six screenshots
    /// missing from a live listing.
    @Test func aBodyReportingPartialFailureEndsFailedWithItsPayloadIntact() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let store = MCPJobStore()
        let executor = MCPToolExecutor(state: state, jobs: store)

        let result = try await executor.runJob(kind: .apply, totalUnits: 44, mode: .sync) { handle in
            handle.progress(completed: 44)
            return MCPJobOutcome(.object(["sets": .array([])]), succeeded: false)
        }
        #expect(try phase(result) == MCPJobPhase.failed.rawValue)
        #expect(try decode(result)["result"] != nil, "the partial payload is what a caller recovers from")
    }

    @Test func aFailingBodyBecomesAFailedJobRatherThanAThrownToolError() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let executor = MCPToolExecutor(state: state, jobs: MCPJobStore())

        let result = try await executor.runJob(kind: .apply, totalUnits: 1, mode: .sync) { _ in
            throw MCPToolError.failed("upload exploded")
        }
        #expect(try phase(result) == MCPJobPhase.failed.rawValue)
        #expect(try (decode(result)["error"] as? String)?.contains("upload exploded") == true)
    }

    @Test func cancellingARunningJobDrivesItToCancelled() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let store = MCPJobStore()
        let executor = MCPToolExecutor(state: state, jobs: store)

        let started = try await executor.runJob(kind: .apply, totalUnits: 10, mode: .async) { _ in
            try await Task.sleep(for: .seconds(30))
            return MCPJobOutcome(.null)
        }
        let jobId = try #require(try decode(started)["job_id"] as? String)

        let cancelled = try executor.cancelSyncJob(MCPArguments(["job_id": .string(jobId)]))
        #expect(try (decode(cancelled)["cancel_requested"] as? Bool) == true)

        var settled = false
        for _ in 0..<100 {
            if store.job(jobId)?.phase == .cancelled { settled = true; break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(settled, "cancellation must actually unwind the body")
    }

    /// Stopping the server abandons whatever is running, and a poller has only the envelope to
    /// read: without the recorded intent it sees a job that still looks like it is progressing.
    @Test func stoppingTheServerMarksItsRunningJobsCancelRequested() {
        let store = MCPJobStore()
        let jobId = store.register(kind: .apply, totalUnits: 10)
        store.attach(Task { _ = try? await Task.sleep(for: .seconds(30)) }, to: jobId)

        store.cancelAll()

        #expect(store.job(jobId)?.cancelRequested == true)
    }

    @Test func pollingAnUnknownJobIsAClientError() async throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let executor = MCPToolExecutor(state: state, jobs: MCPJobStore())
        let result = await executor.call(name: "get_sync_job_status", arguments: ["job_id": .string("job_nope")])
        #expect(result.isError == true)
    }

    @Test func catalogAndDispatchStayInStep() async throws {
        #expect(MCPToolCatalog.tools.count == MCPToolName.allCases.count)
        let names = Set(MCPToolCatalog.tools.map(\.name))
        #expect(names.contains(MCPToolName.getSyncJobStatus.rawValue))
        #expect(names.contains(MCPToolName.cancelSyncJob.rawValue))
    }
}
