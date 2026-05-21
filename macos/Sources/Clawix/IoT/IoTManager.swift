import Foundation
import SwiftUI
import Combine

/// Observable manager for the clawjs-iot daemon.
///
/// Owns:
///   - The HTTP client (`IoTClient`).
///   - The realtime SSE event stream (`/v1/events/stream`).
///   - The cached snapshots the UI binds against: homes, areas, devices,
///     scenes, automations, approvals.
///   - The downloaded tool catalog (`availableTools`).
///
/// The supervisor (`ClawJSServiceManager.shared.snapshots[.iot]`)
/// drives the state machine: any time the service flips to `.ready` /
/// `.readyFromDaemon` we bootstrap; any other state suspends consumers
/// and clears the snapshots so the UI shows the right empty/error
/// surface. The SSE stream keeps the snapshots fresh between fetches.
@MainActor
final class IoTManager: NSObject, ObservableObject {
    typealias AdminTokenOperation = @MainActor () -> String?

    enum State: Equatable {
        case loading
        case bootstrapping
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var lastError: String?

    /// Tool catalog exposed by the daemon.
    @Published private(set) var availableTools: [RemoteToolDescriptor] = []
    @Published private(set) var catalogGeneratedAt: Date?

    /// Cached collections. The supervisor refresh path replaces each one
    /// wholesale; SSE deltas trigger targeted re-fetches.
    @Published private(set) var homes: [HomeRecord] = []
    @Published private(set) var currentHomeId: String?
    @Published private(set) var areas: [AreaRecord] = []
    @Published private(set) var devices: [IoTDeviceRecord] = []
    @Published private(set) var scenes: [SceneRecord] = []
    @Published private(set) var automations: [AutomationRecord] = []
    @Published private(set) var approvals: [ApprovalRecord] = []
    @Published private(set) var pendingApprovalsCount: Int = 0
    @Published private(set) var lastAdapterFailure: String?

    private(set) var client: any IoTClienting

    private var supervisorObserver: AnyCancellable?
    private var bootstrapTask: Task<Void, Never>?
    private var bootstrapTimeoutTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Error>?
    private var bootstrapGeneration = 0
    private var refreshGeneration = 0
    private var actionTasks: [IoTActionKey: IoTActionTask] = [:]
    private var actionGenerations: [IoTActionKey: Int] = [:]
    private let adminTokenOperation: AdminTokenOperation
    private var sseTask: URLSessionDataTask?
    private var sseSession: URLSession!
    private var sseBuffer = Data()

    init(
        client: (any IoTClienting)? = nil,
        adminTokenOperation: AdminTokenOperation? = nil,
        attachSupervisor: Bool = true
    ) {
        self.client = client ?? IoTClient()
        self.adminTokenOperation = adminTokenOperation ?? {
            IoTAdminToken.currentAdminToken()
        }
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = .infinity
        config.waitsForConnectivity = true
        self.sseSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        if attachSupervisor {
            attachSupervisorObserver()
        }
    }

    deinit {
        bootstrapTask?.cancel()
        bootstrapTimeoutTask?.cancel()
        refreshTask?.cancel()
        for task in actionTasks.values {
            task.cancel()
        }
    }

    // MARK: - Supervisor wiring

    private func attachSupervisorObserver() {
        let supervisor = ClawJSServiceManager.shared
        supervisorObserver = supervisor.$snapshots.sink { [weak self] snapshots in
            guard let self else { return }
            guard let snap = snapshots[.iot] else { return }
            switch snap.state {
            case .ready, .readyFromDaemon:
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if case .ready = self.state { return }
                    await self.bootstrap()
                }
            case .crashed, .blocked, .idle, .daemonUnavailable:
                self.cancelSurfaceWork()
                self.disconnectSSE()
                self.devices = []
                self.areas = []
                self.scenes = []
                self.automations = []
                self.approvals = []
                self.pendingApprovalsCount = 0
                self.state = .failed(snap.state.unavailableReason ?? "IoT service is unavailable.")
            case .availableOnDemand:
                self.cancelSurfaceWork()
                self.disconnectSSE()
                self.devices = []
                self.areas = []
                self.scenes = []
                self.automations = []
                self.approvals = []
                self.pendingApprovalsCount = 0
                self.state = .loading
            case .starting:
                self.state = .bootstrapping
            }
        }
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        if case .ready = state { return }
        let generation = nextBootstrapGeneration()
        bootstrapTask?.cancel()
        refreshTask?.cancel()
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.runBootstrap(generation: generation)
        }
        bootstrapTask = task
        await task.value
    }

    private func runBootstrap(generation: Int) async {
        state = .bootstrapping
        bootstrapTimeoutTask?.cancel()
        bootstrapTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, self.bootstrapGeneration == generation else { return }
            if case .bootstrapping = self.state {
                self.state = .failed("IoT service did not become ready within 8 seconds.")
            }
        }
        client.bearerToken = adminTokenOperation()
        do {
            async let toolsTask = client.listTools()
            async let homesTask = client.listHomes()
            let catalog = try await toolsTask
            let homes = try await homesTask
            try Task.checkCancellation()
            guard isCurrentBootstrap(generation) else { return }
            self.availableTools = catalog.tools
            self.catalogGeneratedAt = ISO8601DateFormatter().date(from: catalog.generatedAt)
            self.homes = homes
            self.currentHomeId = homes.first(where: { $0.isDefault })?.id ?? homes.first?.id
            try await refreshAll()
            try Task.checkCancellation()
            guard isCurrentBootstrap(generation) else { return }
            connectSSE()
            state = .ready
            lastError = nil
        } catch is CancellationError {
        } catch {
            guard isCurrentBootstrap(generation) else { return }
            state = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
        finishBootstrapIfCurrent(generation)
    }

    func refreshAll() async throws {
        let generation = nextRefreshGeneration()
        let homeId = currentHomeId
        refreshTask?.cancel()
        let task = Task<Void, Error> { @MainActor [weak self] in
            guard let self else { return }
            try await self.runRefreshAll(generation: generation, homeId: homeId)
        }
        refreshTask = task
        try await task.value
    }

    private func runRefreshAll(generation: Int, homeId: String?) async throws {
        defer { finishRefreshIfCurrent(generation) }
        async let devicesTask = client.listDevices(homeId: homeId)
        async let areasTask = client.listAreas(homeId: homeId)
        async let scenesTask = client.listScenes(homeId: homeId)
        async let automationsTask = client.listAutomations(homeId: homeId)
        async let approvalsTask = client.listApprovals(homeId: homeId)
        let devices = try await devicesTask
        let areas = try await areasTask
        let scenes = try await scenesTask
        let automations = try await automationsTask
        let approvals = try await approvalsTask
        try Task.checkCancellation()
        guard isCurrentRefresh(generation) else { return }
        self.devices = devices
        self.areas = areas
        self.scenes = scenes
        self.automations = automations
        self.approvals = approvals
        self.pendingApprovalsCount = approvals.filter { $0.status == "pending" }.count
    }

    func switchHome(_ homeId: String) async {
        guard currentHomeId != homeId else { return }
        currentHomeId = homeId
        do {
            try await refreshAll()
            lastError = nil
        } catch is CancellationError {
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshCatalog() async {
        guard case .ready = state else { return }
        do {
            let catalog = try await client.listTools()
            availableTools = catalog.tools
            catalogGeneratedAt = ISO8601DateFormatter().date(from: catalog.generatedAt)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - UI-facing actions

    @discardableResult
    func runAction(_ request: IoTActionRequest) async throws -> IoTActionResult {
        let key = IoTActionKey(kind: .runAction, id: actionIdentity(for: request))
        let generation = nextActionGeneration(for: key)
        let result = try await performAction(key: key, generation: generation) {
            try await self.client.runAction(request, homeId: self.currentHomeId)
        }
        // After a successful action the SSE event will re-trigger our
        // snapshot refresh; we kick a manual refresh too so the UI
        // does not wait on the event round-trip when the user just
        // tapped a card.
        scheduleRefreshAfterChange()
        return result
    }

    func activateScene(_ scene: SceneRecord) async throws {
        let key = IoTActionKey(kind: .activateScene, id: scene.id)
        let generation = nextActionGeneration(for: key)
        _ = try await performAction(key: key, generation: generation) {
            try await self.client.activateScene(sceneId: scene.id, homeId: self.currentHomeId)
        }
        scheduleRefreshAfterChange()
    }

    func setAutomationEnabled(_ automation: AutomationRecord, enabled: Bool) async throws {
        let key = IoTActionKey(kind: .setAutomationEnabled, id: "\(automation.id):\(enabled)")
        let generation = nextActionGeneration(for: key)
        _ = try await performAction(key: key, generation: generation) {
            try await self.client.setAutomationEnabled(
                automationId: automation.id,
                enabled: enabled,
                homeId: self.currentHomeId,
            )
        }
        scheduleRefreshAfterChange()
    }

    func runAutomation(_ automation: AutomationRecord) async throws {
        let key = IoTActionKey(kind: .runAutomation, id: automation.id)
        let generation = nextActionGeneration(for: key)
        _ = try await performAction(key: key, generation: generation) {
            try await self.client.runAutomation(automationId: automation.id, homeId: self.currentHomeId)
        }
        scheduleRefreshAfterChange()
    }

    func approveApproval(_ approval: ApprovalRecord) async throws -> IoTActionResult {
        let key = IoTActionKey(kind: .approveApproval, id: approval.id)
        let generation = nextActionGeneration(for: key)
        let result = try await performAction(key: key, generation: generation) {
            try await self.client.approveApproval(approvalId: approval.id, homeId: self.currentHomeId)
        }
        scheduleRefreshAfterChange()
        return result
    }

    func denyApproval(_ approval: ApprovalRecord) async throws {
        let key = IoTActionKey(kind: .denyApproval, id: approval.id)
        let generation = nextActionGeneration(for: key)
        _ = try await performAction(key: key, generation: generation) {
            try await self.client.denyApproval(approvalId: approval.id, homeId: self.currentHomeId)
        }
        scheduleRefreshAfterChange()
    }

    func addDevice(input: IoTClient.AddDeviceInput) async throws -> IoTDeviceRecord {
        var input = input
        if input.homeId == nil { input.homeId = currentHomeId }
        let key = IoTActionKey(kind: .addDevice, id: input.label ?? input.targetRef ?? "default")
        let generation = nextActionGeneration(for: key)
        let device = try await performAction(key: key, generation: generation) {
            try await self.client.addDevice(input: input)
        }
        scheduleRefreshAfterChange()
        return device
    }

    func removeDevice(_ device: IoTDeviceRecord) async throws {
        let key = IoTActionKey(kind: .removeDevice, id: device.id)
        let generation = nextActionGeneration(for: key)
        try await performAction(key: key, generation: generation) {
            try await self.client.removeDevice(deviceId: device.id, homeId: self.currentHomeId)
        }
        scheduleRefreshAfterChange()
    }

    private func performAction<T>(
        key: IoTActionKey,
        generation: Int,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        actionTasks[key]?.cancel()
        let task = Task<T, Error> {
            try await operation()
        }
        actionTasks[key] = IoTActionTask(cancel: { task.cancel() })
        do {
            let value = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation()
            guard isCurrentAction(key: key, generation: generation) else { throw CancellationError() }
            lastError = nil
            finishActionIfCurrent(key: key, generation: generation)
            return value
        } catch is CancellationError {
            finishActionIfCurrent(key: key, generation: generation)
            throw CancellationError()
        } catch {
            guard isCurrentAction(key: key, generation: generation) else { throw CancellationError() }
            lastError = error.localizedDescription
            finishActionIfCurrent(key: key, generation: generation)
            throw error
        }
    }

    private func scheduleRefreshAfterChange() {
        requestRefreshAllReportingErrors()
    }

    private func requestRefreshAllReportingErrors() {
        let generation = nextRefreshGeneration()
        let homeId = currentHomeId
        refreshTask?.cancel()
        refreshTask = Task<Void, Error> { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.runRefreshAll(generation: generation, homeId: homeId)
                guard self.isCurrentRefresh(generation) else { return }
                self.lastError = nil
            } catch is CancellationError {
            } catch {
                guard self.isCurrentRefresh(generation) else { return }
                self.lastError = error.localizedDescription
            }
        }
    }

    func cancelSurfaceWork() {
        bootstrapGeneration += 1
        bootstrapTask?.cancel()
        bootstrapTask = nil
        bootstrapTimeoutTask?.cancel()
        bootstrapTimeoutTask = nil
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        for key in Array(actionGenerations.keys) {
            actionGenerations[key, default: 0] += 1
        }
        for task in actionTasks.values {
            task.cancel()
        }
        actionTasks.removeAll()
        disconnectSSE()
    }

    func startDiscovery(timeoutMs: Int? = nil) async throws {
        let key = IoTActionKey(kind: .startDiscovery, id: "\(timeoutMs ?? -1)")
        let generation = nextActionGeneration(for: key)
        try await performAction(key: key, generation: generation) {
            try await self.client.startDiscovery(timeoutMs: timeoutMs)
        }
    }

    func stopDiscovery() async throws {
        let key = IoTActionKey(kind: .stopDiscovery, id: "default")
        let generation = nextActionGeneration(for: key)
        try await performAction(key: key, generation: generation) {
            try await self.client.stopDiscovery()
        }
    }

    // MARK: - Protocol helpers

    func commissionMatter(pairingCode: String, label: String?) async throws -> [String: Any] {
        var args: [String: Any] = ["pairingCode": pairingCode]
        if let label, !label.isEmpty { args["label"] = label }
        return try await invokeProtocolTool(kind: .commissionMatter, id: label ?? pairingCode, toolId: "iot.matter.commission", arguments: args)
    }

    func startHomeKitBridge(label: String?) async throws -> [String: Any] {
        var args: [String: Any] = [:]
        if let label, !label.isEmpty { args["label"] = label }
        return try await invokeProtocolTool(kind: .startHomeKitBridge, id: label ?? "default", toolId: "iot.homekit.startBridge", arguments: args)
    }

    func connectMqtt(url: String, username: String?, password: String?) async throws -> [String: Any] {
        var args: [String: Any] = ["url": url]
        if let username, !username.isEmpty { args["username"] = username }
        if let password, !password.isEmpty { args["password"] = password }
        return try await invokeProtocolTool(kind: .connectMqtt, id: url, toolId: "iot.mqtt.connect", arguments: args)
    }

    func disconnectMqtt() async throws {
        _ = try await invokeProtocolTool(kind: .disconnectMqtt, id: "default", toolId: "iot.mqtt.disconnect", arguments: [:])
    }

    // MARK: - Cloud helpers

    func connectTuya(appKey: String, appSecret: String, baseUrl: String?) async throws -> [String: Any] {
        var args: [String: Any] = ["appKey": appKey, "appSecret": appSecret]
        if let baseUrl, !baseUrl.isEmpty { args["baseUrl"] = baseUrl }
        return try await invokeProtocolTool(kind: .connectTuya, id: appKey, toolId: "iot.tuya.connect", arguments: args)
    }

    func syncTuya() async throws -> [String: Any] {
        return try await invokeProtocolTool(kind: .syncTuya, id: "default", toolId: "iot.tuya.sync", arguments: [:])
    }

    func disconnectTuya() async throws {
        _ = try await invokeProtocolTool(kind: .disconnectTuya, id: "default", toolId: "iot.tuya.disconnect", arguments: [:])
    }

    func connectGoogleHome(
        publicFulfillmentUrl: String,
        oauthClientId: String,
        oauthClientSecret: String,
        agentUserId: String,
        homeGraphToken: String?,
    ) async throws -> [String: Any] {
        var args: [String: Any] = [
            "publicFulfillmentUrl": publicFulfillmentUrl,
            "oauthClientId": oauthClientId,
            "oauthClientSecret": oauthClientSecret,
            "agentUserId": agentUserId,
        ]
        if let homeGraphToken, !homeGraphToken.isEmpty { args["homeGraphToken"] = homeGraphToken }
        return try await invokeProtocolTool(kind: .connectGoogleHome, id: agentUserId, toolId: "iot.googleHome.connect", arguments: args)
    }

    func disconnectGoogleHome() async throws {
        _ = try await invokeProtocolTool(kind: .disconnectGoogleHome, id: "default", toolId: "iot.googleHome.disconnect", arguments: [:])
    }

    func connectAlexa(
        publicFulfillmentUrl: String,
        oauthClientSecret: String,
        eventGatewayToken: String?,
        eventGatewayUrl: String?,
    ) async throws -> [String: Any] {
        var args: [String: Any] = [
            "publicFulfillmentUrl": publicFulfillmentUrl,
            "oauthClientSecret": oauthClientSecret,
        ]
        if let eventGatewayToken, !eventGatewayToken.isEmpty { args["eventGatewayToken"] = eventGatewayToken }
        if let eventGatewayUrl, !eventGatewayUrl.isEmpty { args["eventGatewayUrl"] = eventGatewayUrl }
        return try await invokeProtocolTool(kind: .connectAlexa, id: publicFulfillmentUrl, toolId: "iot.alexa.connect", arguments: args)
    }

    func disconnectAlexa() async throws {
        _ = try await invokeProtocolTool(kind: .disconnectAlexa, id: "default", toolId: "iot.alexa.disconnect", arguments: [:])
    }

    @discardableResult
    private func invokeProtocolTool(
        kind: IoTActionKey.Kind,
        id: String,
        toolId: String,
        arguments: [String: Any]
    ) async throws -> [String: Any] {
        let key = IoTActionKey(kind: kind, id: id)
        let generation = nextActionGeneration(for: key)
        return try await performAction(key: key, generation: generation) {
            let result = try await self.client.invokeTool(id: toolId, arguments: arguments)
            try result.throwIfFailed()
            return result.value?.asDictionary ?? [:]
        }
    }

    // MARK: - Lookups

    func areaLabel(forId id: String?) -> String? {
        guard let id else { return nil }
        return areas.first(where: { $0.id == id })?.label
    }

    func device(byId id: String) -> IoTDeviceRecord? {
        devices.first(where: { $0.id == id })
    }

    func capability(device: IoTDeviceRecord, key: String) -> CapabilityRecord? {
        device.capabilities.first(where: { $0.key == key })
    }

    // MARK: - Realtime SSE

    private func connectSSE() {
        guard sseTask == nil else { return }
        guard let url = URL(string: "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/events/stream", relativeTo: client.origin) else { return }
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = TimeInterval.infinity
        sseBuffer.removeAll()
        sseTask = sseSession.dataTask(with: request)
        sseTask?.resume()
    }

    private func disconnectSSE() {
        sseTask?.cancel()
        sseTask = nil
    }

    private func nextBootstrapGeneration() -> Int {
        bootstrapGeneration += 1
        return bootstrapGeneration
    }

    private func isCurrentBootstrap(_ generation: Int) -> Bool {
        bootstrapGeneration == generation
    }

    private func finishBootstrapIfCurrent(_ generation: Int) {
        guard isCurrentBootstrap(generation) else { return }
        bootstrapTask = nil
        bootstrapTimeoutTask?.cancel()
        bootstrapTimeoutTask = nil
    }

    private func nextRefreshGeneration() -> Int {
        refreshGeneration += 1
        return refreshGeneration
    }

    private func isCurrentRefresh(_ generation: Int) -> Bool {
        refreshGeneration == generation
    }

    private func finishRefreshIfCurrent(_ generation: Int) {
        guard isCurrentRefresh(generation) else { return }
        refreshTask = nil
    }

    private func nextActionGeneration(for key: IoTActionKey) -> Int {
        let generation = (actionGenerations[key] ?? 0) + 1
        actionGenerations[key] = generation
        return generation
    }

    private func isCurrentAction(key: IoTActionKey, generation: Int) -> Bool {
        actionGenerations[key] == generation
    }

    private func finishActionIfCurrent(key: IoTActionKey, generation: Int) {
        guard isCurrentAction(key: key, generation: generation) else { return }
        actionTasks[key] = nil
        actionGenerations[key] = generation
    }

    private struct IoTActionTask {
        let cancel: () -> Void
    }

    private func actionIdentity(for request: IoTActionRequest) -> String {
        [
            request.homeId ?? currentHomeId ?? "",
            request.selector ?? "",
            request.area ?? "",
            request.family ?? "",
            request.capability ?? "",
            request.action,
            request.targets?.joined(separator: ",") ?? "",
        ].joined(separator: "|")
    }

    private struct IoTActionKey: Hashable {
        let kind: Kind
        let id: String

        enum Kind: Hashable {
            case runAction
            case activateScene
            case setAutomationEnabled
            case runAutomation
            case approveApproval
            case denyApproval
            case addDevice
            case removeDevice
            case startDiscovery
            case stopDiscovery
            case commissionMatter
            case startHomeKitBridge
            case connectMqtt
            case disconnectMqtt
            case connectTuya
            case syncTuya
            case disconnectTuya
            case connectGoogleHome
            case disconnectGoogleHome
            case connectAlexa
            case disconnectAlexa
        }
    }

    fileprivate func handleSSEEvent(type: String, payload: [String: Any]?) {
        switch type {
        case "iot.action.executed":
            scheduleRefreshAfterChange()
        case "iot.approval.created":
            scheduleRefreshAfterChange()
        case "iot.thing.added", "iot.thing.removed":
            scheduleRefreshAfterChange()
        case "iot.adapter.failed":
            if let payload, let note = payload["note"] as? String {
                lastAdapterFailure = note
            }
        default:
            break
        }
    }
}

// MARK: - URLSessionDataDelegate (SSE)

extension IoTManager: URLSessionDataDelegate {
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task { @MainActor [weak self] in
            self?.ingestSSEChunk(data)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor [weak self] in
            self?.sseTask = nil
            // Reconnection is handled implicitly by the supervisor:
            // if the daemon drops, snapshot flips out of .ready and we
            // bootstrap again next time it returns.
        }
    }

    private func ingestSSEChunk(_ chunk: Data) {
        sseBuffer.append(chunk)
        while let range = sseBuffer.range(of: Data("\n\n".utf8)) {
            let raw = sseBuffer.subdata(in: 0..<range.lowerBound)
            sseBuffer.removeSubrange(0..<range.upperBound)
            guard let text = String(data: raw, encoding: .utf8) else { continue }
            var type: String?
            var dataLine = ""
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                if line.hasPrefix("event:") {
                    type = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("data:") {
                    if !dataLine.isEmpty { dataLine.append("\n") }
                    dataLine.append(line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces))
                }
            }
            guard let type else { continue }
            let payload: [String: Any]?
            if dataLine.isEmpty {
                payload = nil
            } else if let bytes = dataLine.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
                payload = json
            } else {
                payload = nil
            }
            handleSSEEvent(type: type, payload: payload)
        }
    }
}
