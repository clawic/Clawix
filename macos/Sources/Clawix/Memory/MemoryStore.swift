import Combine
import Foundation

/// State store for the Memory tab. Mirrors the role the Secrets surface store
/// plays for Secrets: a thin wrapper that owns the HTTP client, exposes
/// `@Published` state for SwiftUI, and routes mutations through the
/// daemon. Memory has no master-password lock, so the state machine is
/// simpler (loading → ready → error).
@MainActor
final class MemoryStore: ObservableObject {
    typealias ListNotesOperation = @MainActor () async throws -> [ClawJSMemoryClient.MemoryNote]
    typealias ListCapturesOperation = @MainActor () async throws -> [ClawJSMemoryClient.Capture]
    typealias StatsOperation = @MainActor () async throws -> ClawJSMemoryClient.MemoryStatsResponse
    typealias SearchOperation = @MainActor (_ query: String) async throws -> ClawJSMemoryClient.SearchResponse
    typealias DoctorOperation = @MainActor () async throws -> ClawJSMemoryClient.DoctorResponse
    typealias CreateNoteOperation = @MainActor (
        _ input: ClawJSMemoryClient.CreateNoteInput
    ) async throws -> ClawJSMemoryClient.CreateNoteResponse
    typealias UpdateNoteOperation = @MainActor (
        _ id: String,
        _ patch: ClawJSMemoryClient.UpdateNotePatch,
        _ editor: String
    ) async throws -> ClawJSMemoryClient.UpdateNoteResponse
    typealias DeleteNoteOperation = @MainActor (_ id: String) async throws -> ClawJSMemoryClient.DeleteNoteResponse
    typealias PromoteCaptureOperation = @MainActor (_ id: String) async throws -> ClawJSMemoryClient.PromoteResponse

    enum State: Equatable {
        case idle
        case loading
        case ready
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var notes: [ClawJSMemoryClient.MemoryNote] = []
    @Published private(set) var captures: [ClawJSMemoryClient.Capture] = []
    @Published private(set) var stats: ClawJSMemoryClient.MemoryStatsResponse?
    @Published private(set) var doctor: ClawJSMemoryClient.DoctorResponse?
    @Published private(set) var isDoctorLoading = false
    @Published private(set) var doctorError: String?
    @Published private(set) var lastSearch: ClawJSMemoryClient.SearchResponse?
    @Published var isSearching: Bool = false

    let client: ClawJSMemoryClient
    private let listNotesOperation: ListNotesOperation
    private let listCapturesOperation: ListCapturesOperation
    private let statsOperation: StatsOperation
    private let searchOperation: SearchOperation
    private let doctorOperation: DoctorOperation
    private let createNoteOperation: CreateNoteOperation
    private let updateNoteOperation: UpdateNoteOperation
    private let deleteNoteOperation: DeleteNoteOperation
    private let promoteCaptureOperation: PromoteCaptureOperation
    private var refreshTask: Task<Void, Never>?
    private var refreshTimeoutTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var createTask: Task<Result<ClawJSMemoryClient.CreateNoteResponse, Swift.Error>, Never>?
    private var createGeneration = 0
    private var updateTasks: [String: Task<Result<ClawJSMemoryClient.UpdateNoteResponse, Swift.Error>, Never>] = [:]
    private var updateGenerations: [String: Int] = [:]
    private var deleteTasks: [String: Task<Result<ClawJSMemoryClient.DeleteNoteResponse, Swift.Error>, Never>] = [:]
    private var deleteGenerations: [String: Int] = [:]
    private var promoteTasks: [String: Task<Result<ClawJSMemoryClient.PromoteResponse, Swift.Error>, Never>] = [:]
    private var promoteGenerations: [String: Int] = [:]
    private var activeSearchQuery: String?
    private var supervisorObserver: AnyCancellable?

    init(
        client: ClawJSMemoryClient = .init(),
        listNotesOperation: ListNotesOperation? = nil,
        listCapturesOperation: ListCapturesOperation? = nil,
        statsOperation: StatsOperation? = nil,
        searchOperation: SearchOperation? = nil,
        doctorOperation: DoctorOperation? = nil,
        createNoteOperation: CreateNoteOperation? = nil,
        updateNoteOperation: UpdateNoteOperation? = nil,
        deleteNoteOperation: DeleteNoteOperation? = nil,
        promoteCaptureOperation: PromoteCaptureOperation? = nil,
        attachSupervisor: Bool = true
    ) {
        self.client = client
        self.listNotesOperation = listNotesOperation ?? {
            try await client.listNotes()
        }
        self.listCapturesOperation = listCapturesOperation ?? {
            try await client.listCaptures()
        }
        self.statsOperation = statsOperation ?? {
            try await client.stats()
        }
        self.searchOperation = searchOperation ?? { query in
            try await client.search(query: query)
        }
        self.doctorOperation = doctorOperation ?? {
            try await client.doctor()
        }
        self.createNoteOperation = createNoteOperation ?? { input in
            try await client.createNote(input)
        }
        self.updateNoteOperation = updateNoteOperation ?? { id, patch, editor in
            try await client.updateNote(id: id, patch: patch, editor: editor)
        }
        self.deleteNoteOperation = deleteNoteOperation ?? { id in
            try await client.deleteNote(id: id)
        }
        self.promoteCaptureOperation = promoteCaptureOperation ?? { id in
            try await client.promoteCapture(id: id)
        }
        if attachSupervisor {
            attachSupervisorObserver()
        }
    }

    deinit {
        refreshTask?.cancel()
        refreshTimeoutTask?.cancel()
        searchTask?.cancel()
        createTask?.cancel()
        for task in updateTasks.values { task.cancel() }
        for task in deleteTasks.values { task.cancel() }
        for task in promoteTasks.values { task.cancel() }
    }

    // MARK: - Loading

    /// Refreshes notes + captures + stats in parallel. Marks `state =
    /// .ready` when everything succeeds; flips to `.error` only when
    /// the notes call fails (captures + stats are best-effort).
    func refresh() async {
        state = .loading
        let generation = nextRefreshGeneration()
        refreshTask?.cancel()
        refreshTimeoutTask?.cancel()
        scheduleRefreshTimeout(generation: generation)
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.runRefresh(generation: generation)
        }
        refreshTask = task
        await task.value
    }

    private func runRefresh(generation: Int) async {
        do {
            async let notesTask = listNotesOperation()
            async let capturesTask: [ClawJSMemoryClient.Capture] = (try? await listCapturesOperation()) ?? []
            async let statsTask: ClawJSMemoryClient.MemoryStatsResponse? = (try? await statsOperation())
            let notes = try await notesTask
            let captures = await capturesTask
            let stats = await statsTask
            try Task.checkCancellation()
            guard isCurrentRefresh(generation) else { return }
            self.notes = notes
            self.captures = captures
            self.stats = stats
            state = .ready
            await refreshActiveSearchIfNeeded()
        } catch is CancellationError {
        } catch let error as ClawJSMemoryClient.Error {
            guard isCurrentRefresh(generation) else { return }
            state = .error(Self.failureMessage(for: error, surface: "memory.refresh"))
        } catch {
            guard isCurrentRefresh(generation) else { return }
            state = .error(Self.failureMessage(for: error, surface: "memory.refresh"))
        }
        finishRefreshIfCurrent(generation)
    }

    /// Just probes the daemon and updates `doctor`. Does not affect
    /// `state` so a doctor refresh from the Settings page does not show
    /// a transient loading shimmer over the list.
    func runDoctor() async {
        guard !isDoctorLoading else { return }
        isDoctorLoading = true
        doctorError = nil
        defer { isDoctorLoading = false }
        do {
            doctor = try await doctorOperation()
        } catch is CancellationError {
        } catch {
            doctorError = Self.failureMessage(for: error, surface: "memory.doctor")
        }
    }

    private static func failureMessage(for error: Error, surface: String) -> String {
        let rawMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return UserFacingFailure.displayMessage(for: rawMessage, surface: surface)
    }

    // MARK: - Search

    /// Debounced search. Cancels the previous in-flight request and
    /// dispatches a new one after 300 ms of typing pause.
    func search(_ query: String) {
        let generation = nextSearchGeneration()
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            activeSearchQuery = nil
            isSearching = false
            lastSearch = nil
            searchTask = nil
            return
        }
        activeSearchQuery = trimmed
        searchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runSearch(query: trimmed, generation: generation, debounce: true)
        }
    }

    func clearSearch() {
        searchGeneration += 1
        searchTask?.cancel()
        searchTask = nil
        activeSearchQuery = nil
        lastSearch = nil
        isSearching = false
    }

    private func refreshActiveSearchIfNeeded() async {
        guard let query = activeSearchQuery else { return }
        let generation = nextSearchGeneration()
        searchTask?.cancel()
        searchTask = nil
        isSearching = true
        await runSearch(query: query, generation: generation, debounce: false)
    }

    private func runSearch(query: String, generation: Int, debounce: Bool) async {
        if debounce {
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }
        }
        do {
            try Task.checkCancellation()
            guard isCurrentSearch(generation), activeSearchQuery == query else { return }
            isSearching = true
            let response = try await searchOperation(query)
            try Task.checkCancellation()
            guard isCurrentSearch(generation), activeSearchQuery == query else { return }
            lastSearch = response
            isSearching = false
            finishSearchIfCurrent(generation)
        } catch is CancellationError {
        } catch {
            guard isCurrentSearch(generation), activeSearchQuery == query else { return }
            lastSearch = nil
            isSearching = false
            finishSearchIfCurrent(generation)
        }
    }

    private func attachSupervisorObserver() {
        supervisorObserver = ClawJSServiceManager.shared.$snapshots.sink { [weak self] snapshots in
            guard let self, let snap = snapshots[.memory] else { return }
            switch snap.state {
            case .ready, .readyFromDaemon:
                switch self.state {
                case .idle, .error:
                    Task { @MainActor [weak self] in await self?.refresh() }
                case .loading, .ready:
                    break
                }
            case .blocked, .crashed, .daemonUnavailable, .idle:
                self.reset(reason: snap.state.unavailableReason ?? "Memory service is unavailable.")
            case .availableOnDemand:
                self.cancelSurfaceWork()
                self.state = .idle
            case .starting:
                if self.state != .ready { self.state = .loading }
            }
        }
    }

    func reset(reason: String) {
        cancelSurfaceWork()
        notes = []
        captures = []
        stats = nil
        state = .error(reason)
    }

    func cancelSurfaceWork() {
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        refreshTimeoutTask?.cancel()
        refreshTimeoutTask = nil
        clearSearch()
        cancelMutationTasks()
        if state == .loading {
            state = .idle
        }
    }

    // MARK: - Mutations

    @discardableResult
    func create(_ input: ClawJSMemoryClient.CreateNoteInput) async throws -> ClawJSMemoryClient.CreateNoteResponse {
        let generation = nextCreateGeneration()
        createTask?.cancel()
        let task = Task<Result<ClawJSMemoryClient.CreateNoteResponse, Swift.Error>, Never> { @MainActor [weak self] in
            guard let self else { return .failure(CancellationError()) }
            return await self.runCreate(input: input, generation: generation)
        }
        createTask = task
        switch await task.value {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }

    @discardableResult
    func update(
        id: String,
        patch: ClawJSMemoryClient.UpdateNotePatch,
        editor: String = "user"
    ) async throws -> ClawJSMemoryClient.UpdateNoteResponse {
        let generation = nextUpdateGeneration(key: id)
        updateTasks[id]?.cancel()
        let task = Task<Result<ClawJSMemoryClient.UpdateNoteResponse, Swift.Error>, Never> { @MainActor [weak self] in
            guard let self else { return .failure(CancellationError()) }
            return await self.runUpdate(id: id, patch: patch, editor: editor, generation: generation)
        }
        updateTasks[id] = task
        switch await task.value {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }

    @discardableResult
    func delete(id: String) async throws -> ClawJSMemoryClient.DeleteNoteResponse {
        let generation = nextDeleteGeneration(key: id)
        deleteTasks[id]?.cancel()
        let task = Task<Result<ClawJSMemoryClient.DeleteNoteResponse, Swift.Error>, Never> { @MainActor [weak self] in
            guard let self else { return .failure(CancellationError()) }
            return await self.runDelete(id: id, generation: generation)
        }
        deleteTasks[id] = task
        switch await task.value {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }

    @discardableResult
    func promote(captureId: String) async throws -> ClawJSMemoryClient.PromoteResponse {
        let generation = nextPromoteGeneration(key: captureId)
        promoteTasks[captureId]?.cancel()
        let task = Task<Result<ClawJSMemoryClient.PromoteResponse, Swift.Error>, Never> { @MainActor [weak self] in
            guard let self else { return .failure(CancellationError()) }
            return await self.runPromote(captureId: captureId, generation: generation)
        }
        promoteTasks[captureId] = task
        switch await task.value {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }

    private func runCreate(
        input: ClawJSMemoryClient.CreateNoteInput,
        generation: Int
    ) async -> Result<ClawJSMemoryClient.CreateNoteResponse, Swift.Error> {
        do {
            let response = try await createNoteOperation(input)
            try Task.checkCancellation()
            guard isCurrentCreate(generation) else { return .failure(CancellationError()) }
            await refresh()
            try Task.checkCancellation()
            guard isCurrentCreate(generation) else { return .failure(CancellationError()) }
            finishCreateIfCurrent(generation)
            return .success(response)
        } catch is CancellationError {
            return .failure(CancellationError())
        } catch {
            guard isCurrentCreate(generation) else { return .failure(CancellationError()) }
            finishCreateIfCurrent(generation)
            return .failure(error)
        }
    }

    private func runUpdate(
        id: String,
        patch: ClawJSMemoryClient.UpdateNotePatch,
        editor: String,
        generation: Int
    ) async -> Result<ClawJSMemoryClient.UpdateNoteResponse, Swift.Error> {
        do {
            let response = try await updateNoteOperation(id, patch, editor)
            try Task.checkCancellation()
            guard isCurrentUpdate(key: id, generation: generation) else { return .failure(CancellationError()) }
            await refresh()
            try Task.checkCancellation()
            guard isCurrentUpdate(key: id, generation: generation) else { return .failure(CancellationError()) }
            finishUpdateIfCurrent(key: id, generation: generation)
            return .success(response)
        } catch is CancellationError {
            return .failure(CancellationError())
        } catch {
            guard isCurrentUpdate(key: id, generation: generation) else { return .failure(CancellationError()) }
            finishUpdateIfCurrent(key: id, generation: generation)
            return .failure(error)
        }
    }

    private func runDelete(
        id: String,
        generation: Int
    ) async -> Result<ClawJSMemoryClient.DeleteNoteResponse, Swift.Error> {
        do {
            let response = try await deleteNoteOperation(id)
            try Task.checkCancellation()
            guard isCurrentDelete(key: id, generation: generation) else { return .failure(CancellationError()) }
            await refresh()
            try Task.checkCancellation()
            guard isCurrentDelete(key: id, generation: generation) else { return .failure(CancellationError()) }
            finishDeleteIfCurrent(key: id, generation: generation)
            return .success(response)
        } catch is CancellationError {
            return .failure(CancellationError())
        } catch {
            guard isCurrentDelete(key: id, generation: generation) else { return .failure(CancellationError()) }
            finishDeleteIfCurrent(key: id, generation: generation)
            return .failure(error)
        }
    }

    private func runPromote(
        captureId: String,
        generation: Int
    ) async -> Result<ClawJSMemoryClient.PromoteResponse, Swift.Error> {
        do {
            let response = try await promoteCaptureOperation(captureId)
            try Task.checkCancellation()
            guard isCurrentPromote(key: captureId, generation: generation) else { return .failure(CancellationError()) }
            await refresh()
            try Task.checkCancellation()
            guard isCurrentPromote(key: captureId, generation: generation) else { return .failure(CancellationError()) }
            finishPromoteIfCurrent(key: captureId, generation: generation)
            return .success(response)
        } catch is CancellationError {
            return .failure(CancellationError())
        } catch {
            guard isCurrentPromote(key: captureId, generation: generation) else { return .failure(CancellationError()) }
            finishPromoteIfCurrent(key: captureId, generation: generation)
            return .failure(error)
        }
    }

    private func scheduleRefreshTimeout(generation: Int) {
        refreshTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, self.isCurrentRefresh(generation) else { return }
            if case .loading = self.state {
                self.state = .error("Memory service did not become ready within 8 seconds.")
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
        refreshTimeoutTask?.cancel()
        refreshTimeoutTask = nil
    }

    private func nextSearchGeneration() -> Int {
        searchGeneration += 1
        return searchGeneration
    }

    private func isCurrentSearch(_ generation: Int) -> Bool {
        searchGeneration == generation
    }

    private func finishSearchIfCurrent(_ generation: Int) {
        guard isCurrentSearch(generation) else { return }
        searchTask = nil
    }

    private func cancelMutationTasks() {
        createGeneration += 1
        createTask?.cancel()
        createTask = nil
        for task in updateTasks.values { task.cancel() }
        updateTasks.removeAll()
        for key in Array(updateGenerations.keys) {
            updateGenerations[key, default: 0] += 1
        }
        for task in deleteTasks.values { task.cancel() }
        deleteTasks.removeAll()
        for key in Array(deleteGenerations.keys) {
            deleteGenerations[key, default: 0] += 1
        }
        for task in promoteTasks.values { task.cancel() }
        promoteTasks.removeAll()
        for key in Array(promoteGenerations.keys) {
            promoteGenerations[key, default: 0] += 1
        }
    }

    private func nextCreateGeneration() -> Int {
        createGeneration += 1
        return createGeneration
    }

    private func isCurrentCreate(_ generation: Int) -> Bool {
        createGeneration == generation
    }

    private func finishCreateIfCurrent(_ generation: Int) {
        guard isCurrentCreate(generation) else { return }
        createTask = nil
    }

    private func nextUpdateGeneration(key: String) -> Int {
        let generation = (updateGenerations[key] ?? 0) + 1
        updateGenerations[key] = generation
        return generation
    }

    private func isCurrentUpdate(key: String, generation: Int) -> Bool {
        updateGenerations[key] == generation
    }

    private func finishUpdateIfCurrent(key: String, generation: Int) {
        guard isCurrentUpdate(key: key, generation: generation) else { return }
        updateTasks.removeValue(forKey: key)
    }

    private func nextDeleteGeneration(key: String) -> Int {
        let generation = (deleteGenerations[key] ?? 0) + 1
        deleteGenerations[key] = generation
        return generation
    }

    private func isCurrentDelete(key: String, generation: Int) -> Bool {
        deleteGenerations[key] == generation
    }

    private func finishDeleteIfCurrent(key: String, generation: Int) {
        guard isCurrentDelete(key: key, generation: generation) else { return }
        deleteTasks.removeValue(forKey: key)
    }

    private func nextPromoteGeneration(key: String) -> Int {
        let generation = (promoteGenerations[key] ?? 0) + 1
        promoteGenerations[key] = generation
        return generation
    }

    private func isCurrentPromote(key: String, generation: Int) -> Bool {
        promoteGenerations[key] == generation
    }

    private func finishPromoteIfCurrent(key: String, generation: Int) {
        guard isCurrentPromote(key: key, generation: generation) else { return }
        promoteTasks.removeValue(forKey: key)
    }
}
