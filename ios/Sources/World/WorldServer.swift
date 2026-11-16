import Foundation
import Network

/// Loopback-only asset server so WKWebView can use standard modules, workers and CORS.
final class WorldServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.irannavigator.world-assets")
    private let directory: URL
    private(set) var origin: URL?
    init(directory: URL) { self.directory = directory.standardizedFileURL.resolvingSymlinksInPath() }
    func start(_ completion: @escaping (Result<URL, Error>) -> Void) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        var completed = false
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self = self, let listener = listener, !completed else { return }
            switch state {
            case .ready:
                guard let port = listener.port else { return }
                completed = true
                let origin = URL(string: "http://127.0.0.1:\(port.rawValue)")!
                self.origin = origin
                DispatchQueue.main.async { completion(.success(origin.appendingPathComponent("assets/world/index.html"))) }
            case .failed(let error):
                completed = true
                DispatchQueue.main.async { completion(.failure(error)) }
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self = self else { connection.cancel(); return }
            connection.start(queue: self.queue)
            self.receive(connection, buffer: Data())
        }
        listener.start(queue: queue)
    }
    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, complete, error in
            guard let self = self, error == nil else { connection.cancel(); return }
            var request = buffer
            if let data = data { request.append(data) }
            guard request.count <= 16384 else { connection.cancel(); return }
            if let text = String(data: request, encoding: .utf8), text.contains("\r\n\r\n") {
                self.respond(connection, request: text)
            } else if complete { connection.cancel() }
            else { self.receive(connection, buffer: request) }
        }
    }
    private func respond(_ connection: NWConnection, request: String) {
        let parts = request.components(separatedBy: "\r\n")[0].split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { reply(connection, status: "405 Method Not Allowed", mime: "text/plain", data: Data()); return }
        let raw = String(parts[1]).components(separatedBy: "?")[0]
        guard let path = raw.removingPercentEncoding, WorldHostPolicy.validAssetPath(path) else {
            reply(connection, status: "403 Forbidden", mime: "text/plain", data: Data()); return
        }
        let file = directory.appendingPathComponent(String(path.dropFirst("/assets/world/".count))).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(directory.path + "/"), let data = try? Data(contentsOf: file), data.count < 12 * 1024 * 1024 else {
            reply(connection, status: "404 Not Found", mime: "text/plain", data: Data()); return
        }
        let types = ["html": "text/html", "mjs": "application/javascript", "js": "application/javascript", "css": "text/css", "svg": "image/svg+xml", "json": "application/json", "webmanifest": "application/manifest+json"]
        reply(connection, status: "200 OK", mime: types[file.pathExtension] ?? "application/octet-stream", data: data)
    }
    private func reply(_ connection: NWConnection, status: String, mime: String, data: Data) {
        var response = Data("HTTP/1.1 \(status)\r\nContent-Type: \(mime); charset=utf-8\r\nContent-Length: \(data.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n".utf8)
        response.append(data)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
    func stop() { listener?.cancel(); listener = nil; origin = nil }
    deinit { stop() }
}

enum WorldHostPolicy {
    static func validAssetPath(_ path: String) -> Bool {
        path.hasPrefix("/assets/world/") && !path.contains("\\") && !path.contains("\0") && !path.split(separator: "/").contains("..")
    }
    static func trusted(_ url: URL?, origin: URL?) -> Bool {
        guard let url = url, let origin = origin else { return false }
        return url.scheme == "http" && url.host == "127.0.0.1" && url.port == origin.port && url.user == nil && url.password == nil && validAssetPath(url.path)
    }
}
