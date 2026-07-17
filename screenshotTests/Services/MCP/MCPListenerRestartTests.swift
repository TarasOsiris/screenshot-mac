import Foundation
import MCP
import Testing
@testable import Screenshot_Bro

/// Regression: NWListener.cancel() releases its socket asynchronously, so stop() must wait for
/// the release — otherwise an immediate restart on the same port fails with EADDRINUSE (the
/// Settings toggle off→on left the server dead).
@Suite(.serialized)
struct MCPListenerRestartTests {

    @Test func immediateStopStartRebindsSamePort() async throws {
        let port: UInt16 = 8794
        for _ in 0..<3 {
            let listener = MCPHTTPListener(port: port) { _ in .ok() }
            try await listener.start()
            await listener.stop()
        }
    }
}
