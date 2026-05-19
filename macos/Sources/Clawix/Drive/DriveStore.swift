import Foundation
import SwiftUI
import Combine

extension Notification.Name {
    static let driveQuickUploadRequested = Notification.Name("clawix.drive.quickUploadRequested")
}

/// Top-level @MainActor orchestrator for the Drive UI. Wraps
/// `ClawJSDriveClient` (HTTP) and `ClawJSDriveRealtimeClient` (WS), owns
/// the auto-login flow, and exposes a SwiftUI-friendly snapshot of items
/// for the active folder + counts + audit tail. Mirrors the app's store
/// pattern: state machine, no hidden globals, all mutations flow through
/// this object so views can drive optimistic updates.
@MainActor
final class DriveStore: ObservableObject {
    typealias AdminTokenOperation = @MainActor () throws -> String

    enum State: Equatable {
        case loading
        case unauthenticated
        case authenticating
        case ready
        case error(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var counts = ClawJSDriveClient.ViewCounts(myDrive: 0, recent: 0, starred: 0, shared: 0, trash: 0)
    @Published var currentParentId: String? = nil
    @Published var currentView: String = "my-drive"
    @Published var query: String = ""
    @Published var items: [ClawJSDriveClient.DriveItem] = []
    @Published var breadcrumbs: [ClawJSDriveClient.DriveItemDetail.Breadcrumb] = []
    @Published var lastError: String? = nil
    @Published var thumbnailCache: [String: Data] = [:]
    @Published var pendingRefresh: Date = Date()

    let client: any ClawJSDriveClienting
    let realtime: any ClawJSDriveRealtimeClienting

    private var refreshTask: Task<Void, Never>?
    private var bootstrapTask: Task<Void, Never>?
    private var bootstrapTimeoutTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var bootGeneration = 0
    private var mutationGeneration = 0
    private let adminTokenOperation: AdminTokenOperation
    private var supervisorObserver: AnyCancellable?

    init(
        client: (any ClawJSDriveClienting)? = nil,
        realtime: (any ClawJSDriveRealtimeClienting)? = nil,
        adminTokenOperation: AdminTokenOperation? = nil,
        attachSupervisor: Bool = true
    ) {
        self.client = client ?? ClawJSDriveClient()
        self.realtime = realtime ?? ClawJSDriveRealtimeClient()
        self.adminTokenOperation = adminTokenOperation ?? {
            try DriveAdminToken.currentAdminToken()
        }
        configureRealtime()
        if attachSupervisor {
            attachSupervisorObserver()
        }
    }

    deinit {
        refreshTask?.cancel()
        bootstrapTask?.cancel()
        bootstrapTimeoutTask?.cancel()
    }

    // MARK: - Lifecycle

    func boot() {
        guard bootstrapTask == nil else { return }
        let generation = nextBootGeneration()
        bootGeneration = generation
        bootstrapTimeoutTask?.cancel()
        bootstrapTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runBoot(generation: generation)
        }
    }

    private func runBoot(generation: Int) async {
        bootstrapTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, self.bootGeneration == generation else { return }
            switch self.state {
            case .loading, .authenticating:
                self.state = .error("Drive service did not become ready within 8 seconds.")
            default:
                break
            }
        }
        await ensureLoggedIn()
        guard isCurrentBoot(generation), !Task.isCancelled else { return }
        guard case .ready = state else {
            finishBootIfCurrent(generation)
            return
        }
        await refresh()
        guard isCurrentBoot(generation), !Task.isCancelled else { return }
        finishBootIfCurrent(generation)
    }

    func ensureLoggedIn() async {
        self.state = .authenticating
        do {
            let token = try adminTokenOperation()
            client.bearerToken = token
            self.realtime.setToken(token)
            self.realtime.subscribe(parentId: nil, itemId: nil, kinds: nil)
            self.state = .ready
        } catch {
            self.state = .error("Drive auth failed: \(error.localizedDescription)")
        }
    }

    func cancelSurfaceWork() {
        bootGeneration += 1
        bootstrapTask?.cancel()
        bootstrapTask = nil
        bootstrapTimeoutTask?.cancel()
        bootstrapTimeoutTask = nil
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        mutationGeneration += 1
        realtime.stop()
    }

    // MARK: - Refresh

    func refresh() async {
        let generation = nextRefreshGeneration()
        let view = currentView
        let parentId = currentParentId
        let textQuery = query.isEmpty ? nil : query
        refreshTask?.cancel()
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.runRefresh(
                generation: generation,
                view: view,
                parentId: parentId,
                query: textQuery,
                delayNanoseconds: nil
            )
        }
        refreshTask = task
        await task.value
    }

    private func requestRefresh(delayNanoseconds: UInt64? = nil) {
        let generation = nextRefreshGeneration()
        let view = currentView
        let parentId = currentParentId
        let textQuery = query.isEmpty ? nil : query
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runRefresh(
                generation: generation,
                view: view,
                parentId: parentId,
                query: textQuery,
                delayNanoseconds: delayNanoseconds
            )
        }
    }

    private func runRefresh(
        generation: Int,
        view: String,
        parentId: String?,
        query: String?,
        delayNanoseconds: UInt64?
    ) async {
        if let delayNanoseconds {
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }
        }
        do {
            async let listing = client.listItems(view: view, parentId: parentId, query: query)
            async let bootstrap = client.bootstrap()
            let result = try await listing
            try Task.checkCancellation()
            guard isCurrentRefresh(generation) else { return }
            items = result.items
            counts = result.counts
            breadcrumbs = result.breadcrumbs
            _ = try? await bootstrap
            try Task.checkCancellation()
            guard isCurrentRefresh(generation) else { return }
            lastError = nil
            pendingRefresh = Date()
        } catch is CancellationError {
        } catch {
            guard isCurrentRefresh(generation) else { return }
            lastError = error.localizedDescription
        }
        finishRefreshIfCurrent(generation)
    }

    // MARK: - Mutations (optimistic where reasonable)

    func setParent(_ parentId: String?) {
        self.currentParentId = parentId
        requestRefresh()
    }

    func setView(_ view: String) {
        self.currentView = view
        self.currentParentId = nil
        requestRefresh()
    }

    func setQuery(_ query: String) {
        self.query = query
        requestRefresh(delayNanoseconds: 200_000_000)
    }

    func createFolder(name: String, parentId: String?) async {
        let generation = currentMutationGeneration()
        do {
            _ = try await client.createFolder(name: name, parentId: parentId ?? currentParentId)
            try Task.checkCancellation()
            guard isCurrentMutation(generation) else { return }
            await refreshIfCurrentMutation(generation)
        } catch is CancellationError {
        } catch {
            publishMutationError(error, generation: generation)
        }
    }

    @discardableResult
    func upload(fileURL: URL, parentId: String?, allowOverwrite: Bool = false) async -> Result<ClawJSDriveClient.DriveItemDetail, ClawJSDriveClient.Error> {
        let generation = currentMutationGeneration()
        do {
            let detail = try await client.upload(filePath: fileURL, parentId: parentId ?? currentParentId, duplicatePolicy: allowOverwrite ? nil : "report")
            try Task.checkCancellation()
            guard isCurrentMutation(generation) else { return .failure(.transport(CancellationError())) }
            await refreshIfCurrentMutation(generation)
            guard isCurrentMutation(generation) else { return .failure(.transport(CancellationError())) }
            return .success(detail)
        } catch let error as ClawJSDriveClient.Error {
            publishMutationError(error, generation: generation)
            return .failure(error)
        } catch is CancellationError {
            return .failure(.transport(CancellationError()))
        } catch {
            publishMutationError(error, generation: generation)
            return .failure(.transport(error))
        }
    }

    func uploadPasted(_ data: Data, suggestedName: String, mimeType: String, parentId: String?) async {
        let generation = currentMutationGeneration()
        do {
            _ = try await client.uploadBytes(data, fileName: suggestedName, mimeType: mimeType, parentId: parentId ?? currentParentId)
            try Task.checkCancellation()
            guard isCurrentMutation(generation) else { return }
            await refreshIfCurrentMutation(generation)
        } catch is CancellationError {
        } catch {
            publishMutationError(error, generation: generation)
        }
    }

    func trash(_ itemId: String) async {
        let generation = currentMutationGeneration()
        do {
            _ = try await client.trashItem(itemId)
            try Task.checkCancellation()
            guard isCurrentMutation(generation) else { return }
            await refreshIfCurrentMutation(generation)
        } catch is CancellationError {
        } catch {
            publishMutationError(error, generation: generation)
        }
    }

    func restore(_ itemId: String) async {
        let generation = currentMutationGeneration()
        do {
            _ = try await client.restoreItem(itemId)
            try Task.checkCancellation()
            guard isCurrentMutation(generation) else { return }
            await refreshIfCurrentMutation(generation)
        } catch is CancellationError {
        } catch {
            publishMutationError(error, generation: generation)
        }
    }

    func delete(_ itemId: String) async {
        let generation = currentMutationGeneration()
        do {
            _ = try await client.deleteItem(itemId)
            try Task.checkCancellation()
            guard isCurrentMutation(generation) else { return }
            await refreshIfCurrentMutation(generation)
        } catch is CancellationError {
        } catch {
            publishMutationError(error, generation: generation)
        }
    }

    func replaceDuplicate(existingId: String, fileURL: URL, parentId: String?) async {
        let generation = currentMutationGeneration()
        do {
            _ = try await client.trashItem(existingId)
            try Task.checkCancellation()
            guard isCurrentMutation(generation) else { return }
            _ = try await client.upload(filePath: fileURL, parentId: parentId ?? currentParentId, duplicatePolicy: nil)
            try Task.checkCancellation()
            guard isCurrentMutation(generation) else { return }
            await refreshIfCurrentMutation(generation)
            guard isCurrentMutation(generation) else { return }
            self.lastError = nil
        } catch is CancellationError {
        } catch {
            guard isCurrentMutation(generation) else { return }
            self.lastError = error.localizedDescription
            await refreshIfCurrentMutation(generation)
        }
    }

    func star(_ itemId: String, starred: Bool) async {
        let generation = currentMutationGeneration()
        do {
            _ = try await client.updateItem(itemId, name: nil, starred: starred, parentId: nil)
            try Task.checkCancellation()
            guard isCurrentMutation(generation) else { return }
            await refreshIfCurrentMutation(generation)
        } catch is CancellationError {
        } catch {
            publishMutationError(error, generation: generation)
        }
    }

    func rename(_ itemId: String, newName: String) async {
        let generation = currentMutationGeneration()
        do {
            _ = try await client.updateItem(itemId, name: newName, starred: nil, parentId: nil)
            try Task.checkCancellation()
            guard isCurrentMutation(generation) else { return }
            await refreshIfCurrentMutation(generation)
        } catch is CancellationError {
        } catch {
            publishMutationError(error, generation: generation)
        }
    }

    func markViewed(_ itemId: String) async {
        let generation = currentMutationGeneration()
        do {
            try await client.markViewed(itemId)
            try Task.checkCancellation()
            guard isCurrentMutation(generation) else { return }
            await refreshIfCurrentMutation(generation)
        } catch is CancellationError {
        } catch {
            publishMutationError(error, generation: generation)
        }
    }

    // MARK: - Thumbnails

    func thumbnail(for itemId: String, size: Int = 256) async -> Data? {
        if let cached = thumbnailCache[itemId] { return cached }
        do {
            let data = try await client.loadThumbnailBytes(itemId, size: size)
            try Task.checkCancellation()
            thumbnailCache[itemId] = data
            return data
        } catch is CancellationError {
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - Realtime wiring

    private func configureRealtime() {
        realtime.onEvent = { [weak self] event in
            guard let self else { return }
            // Refresh listing if event affects current parent or current view.
            if event.parentId == self.currentParentId || event.itemId != nil {
                self.requestRefresh()
            }
        }
        realtime.onDisconnect = { _ in /* backoff handled internally */ }
    }

    private func attachSupervisorObserver() {
        supervisorObserver = ClawJSServiceManager.shared.$snapshots.sink { [weak self] snapshots in
            guard let self, let snap = snapshots[.drive] else { return }
            switch snap.state {
            case .ready, .readyFromDaemon:
                if self.bootstrapTask == nil {
                    self.boot()
                }
            case .blocked, .crashed, .daemonUnavailable, .idle:
                self.cancelSurfaceWork()
                self.items = []
                self.breadcrumbs = []
                self.state = .error(snap.state.unavailableReason ?? "Drive service is unavailable.")
            case .starting:
                if self.state != .ready {
                    self.state = .loading
                }
            }
        }
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

    private func currentMutationGeneration() -> Int {
        mutationGeneration
    }

    private func isCurrentMutation(_ generation: Int) -> Bool {
        mutationGeneration == generation
    }

    private func refreshIfCurrentMutation(_ generation: Int) async {
        guard isCurrentMutation(generation) else { return }
        await refresh()
    }

    private func publishMutationError(_ error: Swift.Error, generation: Int) {
        guard isCurrentMutation(generation) else { return }
        lastError = error.localizedDescription
    }

    private func nextBootGeneration() -> Int {
        bootGeneration += 1
        return bootGeneration
    }

    private func isCurrentBoot(_ generation: Int) -> Bool {
        bootGeneration == generation
    }

    private func finishBootIfCurrent(_ generation: Int) {
        guard isCurrentBoot(generation) else { return }
        bootGeneration = 0
        bootstrapTimeoutTask?.cancel()
        bootstrapTimeoutTask = nil
        bootstrapTask = nil
    }
}
