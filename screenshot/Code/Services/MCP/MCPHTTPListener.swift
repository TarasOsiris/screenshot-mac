#if os(macOS)
import Foundation
import MCP
import Network

/// Minimal loopback-only HTTP/1.1 front end for `StatelessHTTPServerTransport`:
/// parses POST requests and feeds them to `handler`, which returns the SDK response.
actor MCPHTTPListener {
    typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    enum ListenerError: Error, LocalizedError {
        case failed(NWError)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .failed(let error): error.localizedDescription
            case .cancelled: "Listener was cancelled"
            }
        }
    }

    private let port: UInt16
    private let maxBodyBytes: Int
    private let handler: Handler
    /// When non-nil/non-empty, every /mcp request must carry a matching `Authorization: Bearer`.
    private let expectedToken: String?
    private let queue = DispatchQueue(label: "mcp.http.listener")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    init(port: UInt16, expectedToken: String? = nil, maxBodyBytes: Int = 20 * 1024 * 1024, handler: @escaping Handler) {
        self.port = port
        self.expectedToken = expectedToken
        self.maxBodyBytes = maxBodyBytes
        self.handler = handler
    }

    func start() async throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ListenerError.cancelled
        }
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)

        let listener = try NWListener(using: parameters)
        self.listener = listener

        listener.newConnectionHandler = { @Sendable [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            Task { await self.accept(connection) }
        }

        let states = AsyncStream<NWListener.State> { continuation in
            listener.stateUpdateHandler = { @Sendable state in
                continuation.yield(state)
            }
        }
        listener.start(queue: queue)

        for await state in states {
            switch state {
            case .ready:
                listener.stateUpdateHandler = { @Sendable _ in }
                return
            case .failed(let error):
                listener.cancel()
                self.listener = nil
                throw ListenerError.failed(error)
            case .cancelled:
                self.listener = nil
                throw ListenerError.cancelled
            default:
                continue
            }
        }
        throw ListenerError.cancelled
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        connections[ObjectIdentifier(connection)] = connection
        connection.start(queue: queue)
        Task { [weak self] in
            await self?.serve(connection)
            connection.cancel()
            await self?.forget(connection)
        }
    }

    private func forget(_ connection: NWConnection) {
        connections.removeValue(forKey: ObjectIdentifier(connection))
    }

    private func serve(_ connection: NWConnection) async {
        var buffer = Data()

        requestLoop: while true {
            let headerEnd: Range<Data.Index>
            while true {
                if let range = MCPHTTPRequestParser.headerEndRange(in: buffer) {
                    headerEnd = range
                    break
                }
                if buffer.count > MCPHTTPRequestParser.maxHeaderBytes {
                    await sendSimpleResponse(connection, status: 431, close: true)
                    return
                }
                guard let chunk = await receiveChunk(connection) else {
                    return
                }
                buffer.append(chunk)
            }

            let headData = buffer.subdata(in: buffer.startIndex..<headerEnd.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<headerEnd.upperBound)

            guard let head = try? MCPHTTPRequestParser.parseHead(headData) else {
                await sendSimpleResponse(connection, status: 400, close: true)
                return
            }

            if head.hasTransferEncoding {
                await sendSimpleResponse(connection, status: 501, close: true)
                return
            }

            var body: Data? = nil
            if head.method == "POST" {
                guard let length = head.contentLength else {
                    await sendSimpleResponse(connection, status: 411, close: true)
                    return
                }
                if length > maxBodyBytes {
                    await sendSimpleResponse(connection, status: 413, close: true)
                    return
                }
                while buffer.count < length {
                    guard let chunk = await receiveChunk(connection) else {
                        return
                    }
                    buffer.append(chunk)
                }
                body = Data(buffer.prefix(length))
                buffer.removeFirst(length)
            }

            let path = head.path
            guard path == "/mcp" || path == "/mcp/" else {
                await sendSimpleResponse(connection, status: 404, close: head.wantsClose)
                if head.wantsClose { return }
                continue requestLoop
            }

            if !isAuthorized(head) {
                await sendSimpleResponse(connection, status: 401, close: head.wantsClose)
                if head.wantsClose { return }
                continue requestLoop
            }

            let request = HTTPRequest(method: head.method, headers: head.headers, body: body, path: path)
            let response = await handler(request)

            let ok = await send(connection, serialize(response, close: head.wantsClose))
            if !ok || head.wantsClose {
                return
            }
        }
    }

    private func isAuthorized(_ head: MCPHTTPRequestHead) -> Bool {
        Self.authorize(head, expectedToken: expectedToken)
    }

    static func authorize(_ head: MCPHTTPRequestHead, expectedToken: String?) -> Bool {
        guard let expectedToken, !expectedToken.isEmpty else { return true }
        guard let value = head.header("authorization")?.trimmingCharacters(in: .whitespaces),
              value.count > 7,
              value.prefix(7).caseInsensitiveCompare("Bearer ") == .orderedSame
        else { return false }
        return constantTimeEqual(String(value.dropFirst(7)), expectedToken)
    }

    private static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let lhs = Array(a.utf8)
        let rhs = Array(b.utf8)
        guard lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for i in lhs.indices { diff |= lhs[i] ^ rhs[i] }
        return diff == 0
    }

    private func receiveChunk(_ connection: NWConnection) async -> Data? {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { @Sendable data, _, _, _ in
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func send(_ connection: NWConnection, _ data: Data) async -> Bool {
        await withCheckedContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { @Sendable error in
                continuation.resume(returning: error == nil)
            })
        }
    }

    private func sendSimpleResponse(_ connection: NWConnection, status: Int, close: Bool) async {
        var data = Data()
        data.append(contentsOf: Array("HTTP/1.1 \(status) \(Self.reasonPhrase(status))\r\n".utf8))
        data.append(contentsOf: Array("Content-Length: 0\r\nConnection: \(close ? "close" : "keep-alive")\r\n\r\n".utf8))
        _ = await send(connection, data)
    }

    private func serialize(_ response: HTTPResponse, close: Bool) -> Data {
        let body = response.bodyData ?? Data()
        var head = "HTTP/1.1 \(response.statusCode) \(Self.reasonPhrase(response.statusCode))\r\n"
        for (name, value) in response.headers {
            head += "\(name): \(value)\r\n"
        }
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: \(close ? "close" : "keep-alive")\r\n\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }

    private static func reasonPhrase(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 202: "Accepted"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 406: "Not Acceptable"
        case 411: "Length Required"
        case 413: "Payload Too Large"
        case 415: "Unsupported Media Type"
        case 421: "Misdirected Request"
        case 431: "Request Header Fields Too Large"
        case 500: "Internal Server Error"
        case 501: "Not Implemented"
        default: "Status"
        }
    }
}
#endif
