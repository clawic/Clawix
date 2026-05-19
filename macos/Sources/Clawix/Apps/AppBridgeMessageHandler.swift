import AppKit
import Foundation
import WebKit

/// Native side of the `window.clawix` SDK. WebKit calls into here
/// whenever the app posts a message via
/// `window.webkit.messageHandlers.clawix.postMessage(...)`. The handler
/// resolves the corresponding JS Promise by calling
/// `window.__clawixResolve` / `__clawixReject` back on the WKWebView.
///
/// `WKScriptMessageHandlerWithReply` is available since macOS 11; it
/// would let us reply synchronously, but we keep the indirection via
/// `__clawixResolve` so old AppKit deployments and the existing
/// `decidePolicyFor` plumbing stay simple.
@MainActor
final class AppBridgeMessageHandler: NSObject, WKScriptMessageHandler {
    static let messageName = "clawix"

    weak var webView: WKWebView?
    private let slug: String
    private let appsStore: AppsStore
    private weak var appState: AppState?
    private weak var databaseManager: DatabaseManager?
    private let resourceRegistry: AppResourceRegistryStore
    private let surfaceReporter: SurfaceRouteReporter
    private var activeRequests: [String: Task<Void, Never>] = [:]
    /// In-memory KV cache mirroring the on-disk storage file. Reads are
    /// served from cache; writes flush to disk asynchronously so the JS
    /// promise resolves quickly and the disk lags behind by a few ms.
    private var storageCache: [String: AppBridgeAnyCodable] = [:]
    private var storageLoaded = false

    init(
        slug: String,
        appsStore: AppsStore = .shared,
        appState: AppState?,
        databaseManager: DatabaseManager? = nil,
        resourceRegistry: AppResourceRegistryStore = AppResourceRegistryStore(directory: AppResourceRegistryStore.defaultDirectory()),
        surfaceReporter: SurfaceRouteReporter = .noop
    ) {
        self.slug = slug
        self.appsStore = appsStore
        self.appState = appState
        self.databaseManager = databaseManager
        self.resourceRegistry = resourceRegistry
        self.surfaceReporter = surfaceReporter
        super.init()
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        // WebKit dispatches script messages on the main thread, which
        // matches our @MainActor isolation, so we can read the body
        // and dispatch synchronously.
        handle(body: message.body)
    }

    private func handle(body: Any) {
        guard let dict = body as? [String: Any],
              let requestId = dict["requestId"] as? String,
              let op = dict["op"] as? String else {
            return
        }
        let payload = (dict["payload"] as? [String: Any]) ?? [:]
        do {
            switch op {
            case "storage.get":
                let key = (payload["key"] as? String) ?? ""
                ensureStorageLoaded()
                let value = storageCache[key]?.value ?? NSNull()
                resolve(requestId: requestId, value: value)
            case "storage.set":
                let key = (payload["key"] as? String) ?? ""
                let value = payload["value"] ?? NSNull()
                ensureStorageLoaded()
                storageCache[key] = AppBridgeAnyCodable(value)
                persistStorage()
                resolve(requestId: requestId, value: NSNull())
            case "storage.delete":
                let key = (payload["key"] as? String) ?? ""
                ensureStorageLoaded()
                storageCache.removeValue(forKey: key)
                persistStorage()
                resolve(requestId: requestId, value: NSNull())
            case "storage.keys":
                ensureStorageLoaded()
                resolve(requestId: requestId, value: Array(storageCache.keys))
            case "agent.sendMessage":
                let text = (payload["text"] as? String) ?? ""
                try sendMessageToOriginatingChat(text)
                resolve(requestId: requestId, value: NSNull())
            case "agent.callTool":
                // v1: every tool call surfaces a native confirm sheet
                // unless the app has the tool in `permissions.allowedTools`.
                // Runtime tool dispatch requires a bridge frame to
                // ClawJS; for now we gate the permission and reject so
                // apps fail loudly until the tools are wired.
                let tool = (payload["tool"] as? String) ?? ""
                try gateToolCall(tool: tool, requestId: requestId)
            case "capabilities.list":
                resolve(requestId: requestId, value: AppCapabilityCatalog.descriptors.map(\.bridgeValue))
            case "capabilities.riskMap":
                guard let record = appsStore.record(forSlug: slug) else {
                    reject(requestId: requestId, message: "App not found")
                    return
                }
                resolve(requestId: requestId, value: AppCapabilityCatalog.riskMap(for: record).bridgeValue)
            case "db.query":
                startTrackedRequest(requestId: requestId, label: "Database query") { [weak self] in
                    await self?.handleDBQuery(payload: payload, requestId: requestId)
                }
            case "search.query":
                startTrackedRequest(requestId: requestId, label: "Search query") { [weak self] in
                    await self?.handleSearchQuery(payload: payload, requestId: requestId)
                }
            case "resources.list":
                startTrackedRequest(requestId: requestId, label: "Resource list") { [weak self] in
                    await self?.handleResourcesList(payload: payload, requestId: requestId)
                }
            case "resources.read":
                startTrackedRequest(requestId: requestId, label: "Resource read") { [weak self] in
                    await self?.handleResourceRead(payload: payload, requestId: requestId)
                }
            case "request.cancel":
                let target = (payload["requestId"] as? String) ?? requestId
                cancelTrackedRequest(target)
                resolve(requestId: requestId, value: NSNull())
            case "ui.setTitle":
                let title = (payload["title"] as? String) ?? ""
                applyTitle(title)
                resolve(requestId: requestId, value: NSNull())
            case "ui.setBadge":
                // Badge is informational only in v1; just acknowledge.
                resolve(requestId: requestId, value: NSNull())
            case "ui.openExternal":
                let urlString = (payload["url"] as? String) ?? ""
                if let url = URL(string: urlString), url.scheme == "https" || url.scheme == "http" || url.scheme == "mailto" {
                    NSWorkspace.shared.open(url)
                    resolve(requestId: requestId, value: NSNull())
                } else {
                    reject(requestId: requestId, message: "Unsupported URL: \(urlString)")
                }
            default:
                reject(requestId: requestId, message: "Unknown op: \(op)")
            }
        } catch {
            reject(requestId: requestId, message: error.localizedDescription)
        }
    }

    // MARK: - Resolve / reject

    private func resolve(requestId: String, value: Any) {
        guard let webView else { return }
        let payload = encodeForJS(value)
        let js = "window.__clawixResolve && window.__clawixResolve(\(jsonEncoded(requestId)), \(payload));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func reject(requestId: String, message: String) {
        guard let webView else { return }
        let js = "window.__clawixReject && window.__clawixReject(\(jsonEncoded(requestId)), \(jsonEncoded(message)));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func progress(requestId: String, value: [String: Any]) {
        guard let webView else { return }
        let payload = encodeForJS(value)
        let js = "window.__clawixDispatch && window.__clawixDispatch('request.progress', { requestId: \(jsonEncoded(requestId)), progress: \(payload) });"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func partial(requestId: String, value: [String: Any]) {
        guard let webView else { return }
        let payload = encodeForJS(value)
        let js = "window.__clawixDispatch && window.__clawixDispatch('request.partial', { requestId: \(jsonEncoded(requestId)), partial: \(payload) });"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Encode a Swift value as a JS literal. Strings + bools + numbers
    /// pass through JSONEncoder; dicts/arrays do too. NSNull becomes
    /// the literal `null`. Anything we can't encode falls back to null.
    private func encodeForJS(_ value: Any) -> String {
        if value is NSNull { return "null" }
        let wrapped = AppBridgeAnyCodable(value)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        if let data = try? encoder.encode(wrapped),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "null"
    }

    private func jsonEncoded(_ string: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [string], options: [])) ?? Data()
        var s = String(data: data, encoding: .utf8) ?? "[\"\"]"
        // Strip surrounding [ ] to get the encoded scalar.
        if s.hasPrefix("[") { s.removeFirst() }
        if s.hasSuffix("]") { s.removeLast() }
        return s
    }

    // MARK: - Storage

    private var storageURL: URL {
        appsStore.directory(forSlug: slug)
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.appStorageFile, isDirectory: false)
    }

    private func ensureStorageLoaded() {
        guard !storageLoaded else { return }
        storageLoaded = true
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL) else { return }
        if let dict = try? JSONDecoder().decode([String: AppBridgeAnyCodable].self, from: data) {
            storageCache = dict
        }
    }

    private func persistStorage() {
        let url = storageURL
        let snapshot = storageCache
        DispatchQueue.global(qos: .utility).async {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            if let data = try? encoder.encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    // MARK: - Agent integration

    private func sendMessageToOriginatingChat(_ text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let appState,
              let record = appsStore.record(forSlug: slug),
              let chatId = record.createdByChatId else {
            // No originating chat: drop the message but don't error so
            // the JS Promise still resolves; the SDK is best-effort.
            return
        }
        // Mirror the path "user types into composer in chat X" by routing
        // the app-originated text through the standard chat send path.
        appState.dispatchAppMessage(text, toChatId: chatId)
    }

    private func gateToolCall(tool: String, requestId: String) throws {
        guard let record = appsStore.record(forSlug: slug) else {
            reject(requestId: requestId, message: "App not found")
            return
        }
        guard case .allowed = AppCapabilityCatalog.activationGate(for: record) else {
            reject(requestId: requestId, message: "App activation review is required before using this capability")
            return
        }
        guard let descriptor = AppHighRiskActionAudit.descriptor(forTool: tool) else {
            reject(requestId: requestId, message: "Unknown high-risk tool capability: \(tool)")
            return
        }
        guard descriptor.customAppAccess == .approvalRequired else {
            reject(requestId: requestId, message: "Tool capability does not require approval: \(descriptor.id)")
            return
        }
        let declared = record.effectiveDeclaredCapabilities
        guard declared.contains(descriptor.id) else {
            reject(requestId: requestId, message: "App manifest does not declare capability: \(descriptor.id)")
            return
        }

        let auditURL = highRiskActionAuditURL(for: record)
        // Sheet-based approval lives in `AppPermissionPrompt`; AppSurfaceView
        // wires it up. The handler just routes the request id back.
        let prompt = AppPermissionPrompt.shared
        prompt.requestToolApproval(
            appName: record.name,
            tool: tool
        ) { [weak self] decision in
            guard let self else { return }
            switch decision {
            case .denied:
                self.writeHighRiskReceipt(
                    app: record,
                    descriptor: descriptor,
                    tool: tool,
                    decision: .denied,
                    outcome: .denied,
                    auditURL: auditURL
                )
                self.reject(requestId: requestId, message: "User denied tool: \(tool)")
            case .once, .always:
                self.writeHighRiskReceipt(
                    app: record,
                    descriptor: descriptor,
                    tool: tool,
                    decision: decision == .always ? .approvedAlways : .approvedOnce,
                    outcome: .approvalRecordedDispatchUnavailable,
                    auditURL: auditURL
                )
                self.reject(requestId: requestId, message: "Agent tool dispatch is not available in this build")
            }
        }
    }

    private func highRiskActionAuditURL(for record: AppRecord) -> URL {
        appsStore.directory(forSlug: record.slug)
            .appendingPathComponent(AppHighRiskActionAudit.filename, isDirectory: false)
    }

    private func writeHighRiskReceipt(
        app: AppRecord,
        descriptor: AppCapabilityDescriptor,
        tool: String,
        decision: AppHighRiskActionReceipt.Decision,
        outcome: AppHighRiskActionReceipt.Outcome,
        auditURL: URL
    ) {
        do {
            _ = try AppHighRiskActionAudit.append(
                app: app,
                descriptor: descriptor,
                action: tool,
                decision: decision,
                outcome: outcome,
                reason: descriptor.summary,
                auditURL: auditURL
            )
        } catch {
            NSLog("Clawix app high-risk action audit write failed: \(error.localizedDescription)")
        }
    }

    private func applyTitle(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var record = appsStore.record(forSlug: slug) else { return }
        if record.name != trimmed {
            record.name = trimmed
            try? appsStore.update(record)
        }
    }

    // MARK: - Search + DB SDK bridge

    private func startTrackedRequest(
        requestId: String,
        label: String,
        operation: @escaping @MainActor () async -> Void
    ) {
        activeRequests[requestId]?.cancel()
        surfaceReporter.loading(label, progress: 0)
        let task = Task { @MainActor [weak self] in
            await operation()
            self?.activeRequests[requestId] = nil
        }
        activeRequests[requestId] = task
    }

    private func cancelTrackedRequest(_ requestId: String) {
        activeRequests[requestId]?.cancel()
        activeRequests[requestId] = nil
        surfaceReporter.partial("Request cancelled")
    }

    private func reportQueryProgress(
        requestId: String,
        message: String,
        progressValue: Double?,
        partialCount: Int? = nil
    ) {
        surfaceReporter.loading(message, progress: progressValue)
        var value: [String: Any] = ["message": message]
        if let progressValue {
            value["progress"] = min(max(progressValue, 0), 1)
        }
        if let partialCount {
            value["partialCount"] = partialCount
        }
        progress(requestId: requestId, value: value)
    }

    private func handleDBQuery(payload: [String: Any], requestId: String) async {
        do {
            try Task.checkCancellation()
            try requireLocalWideCapability("db.query")
            guard let manager = databaseManager else {
                reject(requestId: requestId, message: "Database bridge is unavailable")
                return
            }
            guard case .ready = manager.state else {
                reject(requestId: requestId, message: "Database service is unavailable")
                return
            }
            let query = try AppBridgeQueryDSL.dbQuery(from: payload)
            reportQueryProgress(
                requestId: requestId,
                message: "Querying \(query.collection)",
                progressValue: 0.15
            )
            try Task.checkCancellation()
            let fetchLimit = query.hasClientSideFilters ? 500 : query.limit
            let response = try await manager.client.listRecords(
                namespaceId: manager.currentNamespace,
                collection: query.collection,
                filter: query.backendFilterJSON,
                sort: query.sortString,
                limit: fetchLimit,
                offset: query.effectiveOffset
            )
            try Task.checkCancellation()
            reportQueryProgress(
                requestId: requestId,
                message: "Filtering \(query.collection)",
                progressValue: 0.75
            )
            let filtered = Array(query.postFilter(response.items).prefix(query.limit))
            let bridgedItems = filtered.map { AppBridgeQueryDSL.bridgeValue(collection: query.collection, record: $0) }
            surfaceReporter.partial("Loaded \(filtered.count) \(query.collection) records")
            partial(requestId: requestId, value: [
                "collection": query.collection,
                "items": bridgedItems,
                "partialCount": bridgedItems.count,
                "source": "db.query"
            ])
            resolve(requestId: requestId, value: [
                "collection": query.collection,
                "items": bridgedItems,
                "limit": query.limit,
                "offset": query.effectiveOffset,
                "total": response.total ?? filtered.count,
                "nextCursor": AppBridgeQueryDSL.nextCursor(
                    offset: query.effectiveOffset,
                    returnedCount: filtered.count,
                    limit: query.limit,
                    total: response.total
                ) ?? NSNull(),
                "facets": AppBridgeQueryDSL.facetBridgeValue(records: filtered, fields: query.facets),
                "source": "db.query"
            ])
            surfaceReporter.ready()
        } catch is CancellationError {
            surfaceReporter.partial("Database query cancelled")
            reject(requestId: requestId, message: "Request cancelled")
        } catch {
            reject(requestId: requestId, message: error.localizedDescription)
        }
    }

    private func handleSearchQuery(payload: [String: Any], requestId: String) async {
        do {
            try Task.checkCancellation()
            try requireLocalWideCapability("search.query")
            guard let manager = databaseManager else {
                reject(requestId: requestId, message: "Search bridge is unavailable")
                return
            }
            guard case .ready = manager.state else {
                reject(requestId: requestId, message: "Search service is unavailable")
                return
            }
            let query = try AppBridgeQueryDSL.searchQuery(from: payload)
            let collections = query.collections.isEmpty ? manager.collections.map(\.name) : query.collections
            let needle = query.query.lowercased()
            var items: [[String: Any]] = []
            var matchedRecords: [(collection: String, record: DBRecord)] = []
            var skipped = 0

            for (index, collection) in collections.enumerated() {
                try Task.checkCancellation()
                guard items.count < query.limit else { break }
                let progressValue = collections.isEmpty ? nil : Double(index) / Double(max(collections.count, 1))
                reportQueryProgress(
                    requestId: requestId,
                    message: "Searching \(collection)",
                    progressValue: progressValue,
                    partialCount: items.count
                )
                let response = try await manager.client.listRecords(
                    namespaceId: manager.currentNamespace,
                    collection: collection,
                    filter: nil,
                    sort: "-updatedAt",
                    limit: 100,
                    offset: 0
                )
                var batch: [[String: Any]] = []
                let matches = response.items.filter { record in
                    record.titleString.lowercased().contains(needle)
                        || record.data.values.contains { $0.stringValue?.lowercased().contains(needle) == true }
                }
                for record in matches {
                    guard items.count < query.limit else { break }
                    if skipped < query.effectiveOffset {
                        skipped += 1
                        continue
                    }
                    let bridged = AppBridgeQueryDSL.bridgeValue(collection: collection, record: record)
                    items.append(bridged)
                    batch.append(bridged)
                    matchedRecords.append((collection, record))
                }
                if !batch.isEmpty {
                    surfaceReporter.partial("Found \(items.count) results")
                    let progressValue = Double(index + 1) / Double(max(collections.count, 1))
                    progress(requestId: requestId, value: [
                        "message": "Partial search results",
                        "progress": progressValue,
                        "partialCount": items.count
                    ])
                    partial(requestId: requestId, value: [
                        "collection": collection,
                        "items": batch,
                        "partialCount": items.count,
                        "progress": progressValue,
                        "source": "search.query"
                    ])
                }
            }

            resolve(requestId: requestId, value: [
                "query": query.query,
                "collections": collections,
                "items": items,
                "limit": query.limit,
                "offset": query.effectiveOffset,
                "nextCursor": AppBridgeQueryDSL.nextCursor(
                    offset: query.effectiveOffset,
                    returnedCount: items.count,
                    limit: query.limit,
                    total: nil
                ) ?? NSNull(),
                "facets": AppBridgeQueryDSL.facetBridgeValue(
                    records: matchedRecords.map(\.record),
                    fields: query.facets
                ),
                "source": "search.query"
            ])
            surfaceReporter.ready()
        } catch is CancellationError {
            surfaceReporter.partial("Search query cancelled")
            reject(requestId: requestId, message: "Request cancelled")
        } catch {
            reject(requestId: requestId, message: error.localizedDescription)
        }
    }

    private func handleResourcesList(payload: [String: Any], requestId: String) async {
        do {
            try Task.checkCancellation()
            try requireLocalWideCapability("resources.read")
            let status = sanitizedOptionalString(payload["status"])
            let kind = sanitizedOptionalString(payload["kind"])
            let registry = resourceRegistry
            reportQueryProgress(
                requestId: requestId,
                message: "Listing resources",
                progressValue: 0.2
            )
            let resources = try await Task.detached {
                try registry.list(status: status, kind: kind)
            }.value
            try Task.checkCancellation()
            let bridgedResources = resources.map(\.bridgeValue)
            partial(requestId: requestId, value: [
                "items": bridgedResources,
                "partialCount": bridgedResources.count,
                "source": "resources.list"
            ])
            resolve(requestId: requestId, value: [
                "items": bridgedResources,
                "source": "resources.list"
            ])
            surfaceReporter.ready()
        } catch is CancellationError {
            surfaceReporter.partial("Resource list cancelled")
            reject(requestId: requestId, message: "Request cancelled")
        } catch {
            reject(requestId: requestId, message: error.localizedDescription)
        }
    }

    private func handleResourceRead(payload: [String: Any], requestId: String) async {
        do {
            try Task.checkCancellation()
            try requireLocalWideCapability("resources.read")
            let id = ((payload["id"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else {
                reject(requestId: requestId, message: "resources.read requires an id.")
                return
            }
            let maxBytes = payload["maxBytes"] as? Int ?? 64_000
            let registry = resourceRegistry
            reportQueryProgress(
                requestId: requestId,
                message: "Reading resource",
                progressValue: 0.2
            )
            let result = try await Task.detached {
                try registry.read(id, maxBytes: maxBytes)
            }.value
            try Task.checkCancellation()
            partial(requestId: requestId, value: result.bridgeValue)
            resolve(requestId: requestId, value: result.bridgeValue)
            surfaceReporter.ready()
        } catch is CancellationError {
            surfaceReporter.partial("Resource read cancelled")
            reject(requestId: requestId, message: "Request cancelled")
        } catch {
            reject(requestId: requestId, message: error.localizedDescription)
        }
    }

    private func sanitizedOptionalString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func requireLocalWideCapability(_ capabilityId: String) throws {
        guard let record = appsStore.record(forSlug: slug) else {
            throw AppBridgeCapabilityError.appNotFound
        }
        guard case .allowed = AppCapabilityCatalog.activationGate(for: record) else {
            throw AppBridgeCapabilityError.activationRequired
        }
        guard let descriptor = AppCapabilityCatalog.descriptor(id: capabilityId),
              descriptor.customAppAccess == .localWide else {
            throw AppBridgeCapabilityError.capabilityNotAllowed(capabilityId)
        }

        let declared = record.effectiveDeclaredCapabilities
        if declared.isEmpty {
            if record.effectiveOriginClass == .localUserAuthored || record.effectiveOriginClass == .system {
                return
            }
            throw AppBridgeCapabilityError.capabilityNotDeclared(capabilityId)
        }
        guard declared.contains(capabilityId) else {
            throw AppBridgeCapabilityError.capabilityNotDeclared(capabilityId)
        }
    }
}

private enum AppBridgeCapabilityError: LocalizedError {
    case appNotFound
    case activationRequired
    case capabilityNotAllowed(String)
    case capabilityNotDeclared(String)

    var errorDescription: String? {
        switch self {
        case .appNotFound:
            return "App not found"
        case .activationRequired:
            return "App activation review is required before using this capability"
        case .capabilityNotAllowed(let id):
            return "Capability is not available to custom apps: \(id)"
        case .capabilityNotDeclared(let id):
            return "App manifest does not declare capability: \(id)"
        }
    }
}

// MARK: - AnyCodable helper

/// Heterogeneous JSON-friendly value used to round-trip arbitrary
/// payloads from JS through Swift's Codable encoding. Reads `value`
/// for inspection; encoding goes through JSON via type switching.
struct AppBridgeAnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self.value = NSNull()
        } else if let b = try? c.decode(Bool.self) {
            self.value = b
        } else if let i = try? c.decode(Int.self) {
            self.value = i
        } else if let d = try? c.decode(Double.self) {
            self.value = d
        } else if let s = try? c.decode(String.self) {
            self.value = s
        } else if let arr = try? c.decode([AppBridgeAnyCodable].self) {
            self.value = arr.map(\.value)
        } else if let dict = try? c.decode([String: AppBridgeAnyCodable].self) {
            self.value = dict.mapValues(\.value)
        } else {
            self.value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try c.encodeNil()
        case let v as Bool:
            try c.encode(v)
        case let v as Int:
            try c.encode(v)
        case let v as Int64:
            try c.encode(v)
        case let v as Double:
            try c.encode(v)
        case let v as Float:
            try c.encode(Double(v))
        case let v as String:
            try c.encode(v)
        case let v as [Any]:
            try c.encode(v.map(AppBridgeAnyCodable.init))
        case let v as [String: Any]:
            try c.encode(v.mapValues(AppBridgeAnyCodable.init))
        case let v as NSNumber:
            // NSNumber covers most JS primitives that come through
            // WebKit's bridge: distinguish bool by ObjC type.
            if String(cString: v.objCType) == "c" {
                try c.encode(v.boolValue)
            } else if CFGetTypeID(v) == CFBooleanGetTypeID() {
                try c.encode(v.boolValue)
            } else if v.stringValue.contains(".") {
                try c.encode(v.doubleValue)
            } else {
                try c.encode(v.int64Value)
            }
        default:
            try c.encodeNil()
        }
    }
}
