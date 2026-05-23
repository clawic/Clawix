import Foundation
import Network

/// Loopback-only control endpoint for an agent instance. Lets the dev
/// provisioner drive THIS process's own UI (inventory, click, type, capture,
/// state, close, quit) without the shared cursor, without bringing windows to
/// the front, and in parallel with other instances.
///
/// This is a powerful surface, so it is fenced in hard:
///   - created only when CLAWIX_AGENT_INSTANCE=1 (never in user builds),
///   - bound to 127.0.0.1 only,
///   - every request must carry the per-instance owner token.
final class ClxControlServer {
    private let port: UInt16
    private let token: String
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "clawix.control.server")

    init(port: UInt16, token: String) {
        self.port = port
        self.token = token
    }

    func start() {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host("127.0.0.1"), port: nwPort)
        do {
            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    NSLog("Clawix control server failed: \(error)")
                }
            }
            listener.start(queue: queue)
            self.listener = listener
            NSLog("Clawix control server listening on 127.0.0.1:\(port)")
        } catch {
            NSLog("Clawix control server could not start on \(port): \(error)")
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(connection, buffer: Data())
    }

    private func readRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var accumulated = buffer
            if let data { accumulated.append(data) }
            if let request = ClxHTTPRequest(accumulated) {
                self.handle(request, on: connection)
                return
            }
            if isComplete || error != nil {
                self.respond(connection, status: 400, json: ["error": "malformed request"])
                return
            }
            self.readRequest(connection, buffer: accumulated)
        }
    }

    private func handle(_ request: ClxHTTPRequest, on connection: NWConnection) {
        let parsed = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
        let body = parsed ?? [:]
        guard let provided = body["token"] as? String, provided == token else {
            respond(connection, status: 401, json: ["error": "unauthorized"])
            return
        }
        let verb = request.path.split(separator: "/").last.map(String.init) ?? ""
        DispatchQueue.main.async {
            let result = MainActor.assumeIsolated {
                ClxControlHandlers.handle(verb: verb, args: body)
            }
            self.respond(connection, status: result.status, json: result.json)
        }
    }

    private func respond(_ connection: NWConnection, status: Int, json: [String: Any]) {
        let payload = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        var head = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "ERROR")\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(payload.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(payload)
        connection.send(content: out, completion: .contentProcessed { _ in connection.cancel() })
    }
}

/// Minimal HTTP/1.1 request parse: returns nil until headers and the full
/// Content-Length body have arrived, so the caller keeps reading.
private struct ClxHTTPRequest {
    let method: String
    let path: String
    let body: Data

    init?(_ data: Data) {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data.subdata(in: data.startIndex..<headerEnd.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        method = String(parts[0])
        path = String(parts[1])

        var contentLength = 0
        for line in lines.dropFirst() where line.lowercased().hasPrefix("content-length:") {
            let raw = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
            contentLength = Int(raw) ?? 0
        }
        let bodyStart = headerEnd.upperBound
        let available = data.distance(from: bodyStart, to: data.endIndex)
        if available < contentLength { return nil }
        let bodyEnd = data.index(bodyStart, offsetBy: contentLength)
        body = data.subdata(in: bodyStart..<bodyEnd)
    }
}
