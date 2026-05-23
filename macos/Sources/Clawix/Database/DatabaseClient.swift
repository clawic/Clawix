import Foundation

protocol DatabaseClienting {
    var bearerToken: String? { get set }
    var origin: URL { get }

    func ensureNamespace(id: String, displayName: String?) async throws -> DBNamespace
    func listCollections(namespaceId: String) async throws -> [DBCollection]
    func updateCollection(
        namespaceId: String,
        name: String,
        displayName: String,
        fields: [DBFieldDefinition],
        indexes: [DBIndexDefinition]
    ) async throws -> DBCollection
    func listRecords(
        namespaceId: String,
        collection: String,
        filter: [String: Any]?,
        sort: String?,
        limit: Int?,
        offset: Int?
    ) async throws -> DBListResponse<DBRecord>
    func createRecord(namespaceId: String, collection: String, data: [String: DBJSON]) async throws -> DBRecord
    func updateRecord(namespaceId: String, collection: String, id: String, data: [String: DBJSON]) async throws -> DBRecord
    func deleteRecord(namespaceId: String, collection: String, id: String) async throws -> Bool
    func downloadFile(fileId: String) async throws -> Data
    @available(*, deprecated, message: "Use the fileURL upload overload so large files do not need to be held in memory.")
    func uploadFile(
        namespaceId: String,
        collectionName: String?,
        recordId: String?,
        filename: String,
        contentType: String,
        data: Data
    ) async throws -> DBFileAsset
    func uploadFile(
        namespaceId: String,
        collectionName: String?,
        recordId: String?,
        fileURL: URL,
        filename: String,
        contentType: String
    ) async throws -> DBFileAsset
}

extension DatabaseClienting {
    func ensureNamespace(id: String) async throws -> DBNamespace {
        try await ensureNamespace(id: id, displayName: nil)
    }
}

/// Full HTTP client for the bundled `@clawjs/database` daemon.
/// Wraps the REST surface exposed by `packages/clawjs-database/src/app.ts`.
///
/// The client is a struct holding a bearer token; instances are cheap to
/// copy. `DatabaseManager` owns a single live instance and refreshes the
/// JWT before it expires.
struct DatabaseClient {

    enum Error: Swift.Error, LocalizedError {
        case serviceNotReady
        case invalidURL
        case http(status: Int, body: String?)
        case decoding(Swift.Error)
        case transport(Swift.Error)
        case missingToken

        var errorDescription: String? {
            switch self {
            case .serviceNotReady:
                return "ClawJS database service is not running."
            case .invalidURL:
                return "Could not build a URL for the database service."
            case .http(let status, let body):
                return "Database returned HTTP \(status)" + (body.map { ": \($0)" } ?? "")
            case .decoding(let error):
                return "Could not decode database response: \(error.localizedDescription)"
            case .transport(let error):
                return "Could not reach database service: \(error.localizedDescription)"
            case .missingToken:
                return "Database call requires authentication; no JWT yet."
            }
        }
    }

    var bearerToken: String?
    let origin: URL

    init(
        bearerToken: String? = nil,
        origin: URL = URL(string: "http://127.0.0.1:\(ClawJSService.database.port)")!
    ) {
        self.bearerToken = bearerToken
        self.origin = origin
    }

    // MARK: - Health

    struct HealthResponse: Codable, Equatable {
        let ok: Bool
        let service: String
        let host: String
        let port: Int
    }

    func probeHealth() async throws -> HealthResponse {
        try await get("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/health", authenticated: false)
    }

    // MARK: - Auth

    struct LoginResponse: Codable, Equatable {
        let accessToken: String
        let admin: Admin

        struct Admin: Codable, Equatable {
            let id: String
            let email: String
        }
    }

    struct BootstrapResponse: Codable, Equatable {
        let accessToken: String
        let admin: LoginResponse.Admin
        let created: Bool?
    }

    /// Idempotent. First call creates the admin; subsequent calls return
    /// a fresh JWT for the same credential. 401 if the email exists with
    /// a different password.
    func bootstrapAdmin(email: String, password: String) async throws -> BootstrapResponse {
        try await post("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/auth/admin/bootstrap", body: [
            "email": email,
            "password": password,
        ], authenticated: false)
    }

    func loginAdmin(email: String, password: String) async throws -> LoginResponse {
        try await post("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/auth/admin/login", body: [
            "email": email,
            "password": password,
        ], authenticated: false)
    }

    // MARK: - Namespaces

    private struct NamespacesEnvelope: Codable {
        let items: [DBNamespace]
    }

    func listNamespaces() async throws -> [DBNamespace] {
        let env: NamespacesEnvelope = try await get("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/namespaces")
        return env.items
    }

    /// Idempotent: PUT /v1/namespaces/:id creates if missing, otherwise
    /// returns existing. Backend seeds built-in collections on creation
    /// and on each call.
    func ensureNamespace(id: String, displayName: String? = nil) async throws -> DBNamespace {
        try await request(
            method: "PUT",
            path: "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/namespaces/\(id)",
            body: ["displayName": displayName ?? id]
        )
    }

    // MARK: - Collections

    private struct CollectionsEnvelope: Codable {
        let items: [DBCollection]
    }

    func listCollections(namespaceId: String) async throws -> [DBCollection] {
        let env: CollectionsEnvelope = try await get("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/namespaces/\(namespaceId)/collections")
        return env.items
    }

    func getCollection(namespaceId: String, name: String) async throws -> DBCollection {
        try await get("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/namespaces/\(namespaceId)/collections/\(name)")
    }

    func updateCollection(
        namespaceId: String,
        name: String,
        displayName: String,
        fields: [DBFieldDefinition],
        indexes: [DBIndexDefinition]
    ) async throws -> DBCollection {
        try await request(
            method: "PATCH",
            path: "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/namespaces/\(namespaceId)/collections/\(name)",
            body: [
                "displayName": displayName,
                "fields": fields.map(Self.fieldBody),
                "indexes": indexes.map(Self.indexBody),
            ]
        )
    }

    // MARK: - Records

    func listRecords(
        namespaceId: String,
        collection: String,
        filter: [String: Any]? = nil,
        sort: String? = nil,
        limit: Int? = 200,
        offset: Int? = 0
    ) async throws -> DBListResponse<DBRecord> {
        var components = URLComponents()
        components.path = "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/namespaces/\(namespaceId)/collections/\(collection)/records"
        var items: [URLQueryItem] = []
        if let filter, let data = try? JSONSerialization.data(withJSONObject: filter),
           let str = String(data: data, encoding: .utf8) {
            items.append(URLQueryItem(name: "filter", value: str))
        }
        if let sort { items.append(URLQueryItem(name: "sort", value: sort)) }
        if let limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let offset { items.append(URLQueryItem(name: "offset", value: String(offset))) }
        components.queryItems = items.isEmpty ? nil : items
        let path = components.url(relativeTo: origin)?.path ?? components.path
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return try await get("\(path)\(query)")
    }

    func getRecord(namespaceId: String, collection: String, id: String) async throws -> DBRecord {
        try await get("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/namespaces/\(namespaceId)/collections/\(collection)/records/\(id)")
    }

    func createRecord(
        namespaceId: String,
        collection: String,
        data: [String: DBJSON]
    ) async throws -> DBRecord {
        let body: [String: Any] = data.mapValues { $0.foundationValue }
        return try await post(
            "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/namespaces/\(namespaceId)/collections/\(collection)/records",
            body: body
        )
    }

    func updateRecord(
        namespaceId: String,
        collection: String,
        id: String,
        data: [String: DBJSON]
    ) async throws -> DBRecord {
        let body: [String: Any] = data.mapValues { $0.foundationValue }
        return try await request(
            method: "PATCH",
            path: "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/namespaces/\(namespaceId)/collections/\(collection)/records/\(id)",
            body: body
        )
    }

    @discardableResult
    func deleteRecord(namespaceId: String, collection: String, id: String) async throws -> Bool {
        let env: OkEnvelope = try await request(
            method: "DELETE",
            path: "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/namespaces/\(namespaceId)/collections/\(collection)/records/\(id)",
            body: nil
        )
        return env.ok
    }

    // MARK: - Files

    private struct FilesEnvelope: Codable { let items: [DBFileAsset] }
    private struct OkEnvelope: Codable { let ok: Bool }

    func listFiles(namespaceId: String) async throws -> [DBFileAsset] {
        let env: FilesEnvelope = try await get("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/namespaces/\(namespaceId)/files")
        return env.items
    }

    @available(*, deprecated, message: "Use the fileURL upload overload so large files do not need to be held in memory.")
    func uploadFile(
        namespaceId: String,
        collectionName: String?,
        recordId: String?,
        filename: String,
        contentType: String,
        data: Data
    ) async throws -> DBFileAsset {
        let tempSourceURL = try Self.writeTemporaryUploadSource(data: data)
        defer { try? FileManager.default.removeItem(at: tempSourceURL) }
        return try await uploadFile(
            namespaceId: namespaceId,
            collectionName: collectionName,
            recordId: recordId,
            fileURL: tempSourceURL,
            filename: filename,
            contentType: contentType
        )
    }

    func uploadFile(
        namespaceId: String,
        collectionName: String?,
        recordId: String?,
        fileURL: URL,
        filename: String,
        contentType: String
    ) async throws -> DBFileAsset {
        guard let token = bearerToken else { throw Error.missingToken }
        let url = URL(string: "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/files", relativeTo: origin)!.absoluteURL
        let multipart = try Self.makeMultipartUploadBody(
            namespaceId: namespaceId,
            collectionName: collectionName,
            recordId: recordId,
            sourceFileURL: fileURL,
            filename: filename,
            contentType: contentType
        )
        defer { try? FileManager.default.removeItem(at: multipart.fileURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(multipart.boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(String(multipart.contentLength), forHTTPHeaderField: "Content-Length")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (responseData, response) = try await uploadTask(request, fromFile: multipart.fileURL)
        try Self.validate(response: response, body: responseData)
        return try Self.decoder.decode(DBFileAsset.self, from: responseData)
    }

    struct MultipartUploadBody {
        let fileURL: URL
        let boundary: String
        let contentLength: Int64
    }

    static func makeMultipartUploadBody(
        namespaceId: String,
        collectionName: String?,
        recordId: String?,
        sourceFileURL: URL,
        filename: String,
        contentType: String
    ) throws -> MultipartUploadBody {
        let boundary = "----DatabaseClientBoundary\(UUID().uuidString)"
        let tempURL = ClawixDatabaseRoutes.multipartUploadBodyURL()
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: tempURL)
        do {
            try writeMultipartField(output, boundary: boundary, name: "namespaceId", value: namespaceId)
            if let collectionName {
                try writeMultipartField(output, boundary: boundary, name: "collectionName", value: collectionName)
            }
            if let recordId {
                try writeMultipartField(output, boundary: boundary, name: "recordId", value: recordId)
            }
            try writeString("--\(boundary)\r\n", to: output)
            try writeString("Content-Disposition: form-data; name=\"file\"; filename=\"\(escapeMultipartValue(filename))\"\r\n", to: output)
            try writeString("Content-Type: \(contentType)\r\n\r\n", to: output)
            try appendFile(sourceFileURL, to: output)
            try writeString("\r\n--\(boundary)--\r\n", to: output)
            try output.close()
        } catch {
            try? output.close()
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
        let values = try tempURL.resourceValues(forKeys: [.fileSizeKey])
        return MultipartUploadBody(
            fileURL: tempURL,
            boundary: boundary,
            contentLength: Int64(values.fileSize ?? 0)
        )
    }

    private static func writeTemporaryUploadSource(data: Data) throws -> URL {
        let tempURL = ClawixDatabaseRoutes.uploadSourceURL()
        try data.write(to: tempURL, options: .atomic)
        return tempURL
    }

    private static func writeMultipartField(_ handle: FileHandle, boundary: String, name: String, value: String) throws {
        try writeString("--\(boundary)\r\n", to: handle)
        try writeString("Content-Disposition: form-data; name=\"\(escapeMultipartValue(name))\"\r\n\r\n", to: handle)
        try writeString("\(value)\r\n", to: handle)
    }

    private static func appendFile(_ fileURL: URL, to handle: FileHandle) throws {
        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        while true {
            guard let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty else { break }
            try handle.write(contentsOf: chunk)
        }
    }

    private static func writeString(_ string: String, to handle: FileHandle) throws {
        if let data = string.data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
    }

    private static func escapeMultipartValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
    }

    func downloadFile(fileId: String) async throws -> Data {
        guard let token = bearerToken else { throw Error.missingToken }
        let url = URL(string: "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/files/\(fileId)", relativeTo: origin)!.absoluteURL
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await dataTask(request)
        try Self.validate(response: response, body: data)
        return data
    }

    @discardableResult
    func deleteFile(fileId: String) async throws -> Bool {
        let env: OkEnvelope = try await request(method: "DELETE", path: "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/files/\(fileId)", body: nil)
        return env.ok
    }

    // MARK: - Tokens (read-only from the app; CLI handles writes)

    private struct TokensEnvelope: Codable { let items: [DBScopedToken] }

    func listScopedTokens(namespaceId: String) async throws -> [DBScopedToken] {
        let env: TokensEnvelope = try await get("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/namespaces/\(namespaceId)/tokens")
        return env.items
    }

    // MARK: - Transport

    private static let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        return dec
    }()

    private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        return enc
    }()

    private static func fieldBody(_ field: DBFieldDefinition) -> [String: Any] {
        var body: [String: Any] = [
            "name": field.name,
            "type": field.type.rawValue,
        ]
        if let required = field.required { body["required"] = required }
        if let options = field.options { body["options"] = options }
        if let relation = field.relation {
            body["relation"] = ["collectionName": relation.collectionName]
        }
        if let min = field.min { body["min"] = min }
        if let max = field.max { body["max"] = max }
        if let minLength = field.minLength { body["minLength"] = minLength }
        if let maxLength = field.maxLength { body["maxLength"] = maxLength }
        if let pattern = field.pattern { body["pattern"] = pattern }
        if let unique = field.unique { body["unique"] = unique }
        if let enumScale = field.enumScale { body["enumScale"] = enumScale }
        if let barcodeKind = field.barcodeKind { body["barcodeKind"] = barcodeKind }
        if let durationDisplayUnit = field.durationDisplayUnit { body["durationDisplayUnit"] = durationDisplayUnit }
        return body
    }

    private static func indexBody(_ index: DBIndexDefinition) -> [String: Any] {
        var body: [String: Any] = [
            "name": index.name,
            "fields": index.fields,
        ]
        if let unique = index.unique { body["unique"] = unique }
        return body
    }

    private func get<T: Decodable>(_ path: String, authenticated: Bool = true) async throws -> T {
        try await request(method: "GET", path: path, body: nil, authenticated: authenticated)
    }

    private func post<T: Decodable>(_ path: String, body: Any, authenticated: Bool = true) async throws -> T {
        try await request(method: "POST", path: path, body: body, authenticated: authenticated)
    }

    private func request<T: Decodable>(
        method: String,
        path: String,
        body: Any?,
        authenticated: Bool = true
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: origin)?.absoluteURL else {
            throw Error.invalidURL
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated {
            guard let token = bearerToken else { throw Error.missingToken }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                throw Error.decoding(error)
            }
        }
        let (data, response) = try await dataTask(req)
        try Self.validate(response: response, body: data)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw Error.decoding(error)
        }
    }

    private static func validate(response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if !(200..<300).contains(http.statusCode) {
            let string = String(data: body, encoding: .utf8)
            throw Error.http(status: http.statusCode, body: string)
        }
    }

    private func dataTask(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw Error.transport(error)
        }
    }

    private func uploadTask(_ request: URLRequest, fromFile fileURL: URL) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.upload(for: request, fromFile: fileURL)
        } catch {
            throw Error.transport(error)
        }
    }
}

extension DatabaseClient: DatabaseClienting {}
