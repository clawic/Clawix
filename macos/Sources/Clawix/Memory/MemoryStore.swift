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
    @Published private(set) var lastSearch: ClawJSMemoryClient.SearchResponse?
    @Published var isSearching: Bool = false

    let client: ClawJSMemoryClient
    private let listNotesOperation: ListNotesOperation
    private let listCapturesOperation: ListCapturesOperation
    private let statsOperation: StatsOperation
    private let searchOperation: SearchOperation
    private let doctorOperation: DoctorOperation
    private var refreshTask: Task<Void, Never>?
    private var refreshTimeoutTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var activeSearchQuery: String?
    private var supervisorObserver: AnyCancellable?

    init(
        client: ClawJSMemoryClient = .init(),
        listNotesOperation: ListNotesOperation? = nil,
        listCapturesOperation: ListCapturesOperation? = nil,
        statsOperation: StatsOperation? = nil,
        searchOperation: SearchOperation? = nil,
        doctorOperation: DoctorOperation? = nil,
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
        if attachSupervisor {
            attachSupervisorObserver()
        }
    }

    deinit {
        refreshTask?.cancel()
        refreshTimeoutTask?.cancel()
        searchTask?.cancel()
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
            state = .error(error.localizedDescription)
        } catch {
            guard isCurrentRefresh(generation) else { return }
            state = .error(error.localizedDescription)
        }
        finishRefreshIfCurrent(generation)
    }

    /// Just probes the daemon and updates `doctor`. Does not affect
    /// `state` so a doctor refresh from the Settings page does not show
    /// a transient loading shimmer over the list.
    func runDoctor() async {
        doctor = try? await doctorOperation()
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
            case .starting:
                if self.state != .ready { self.state = .loading }
            }
        }
    }

    func reset(reason: String) {
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        refreshTimeoutTask?.cancel()
        refreshTimeoutTask = nil
        clearSearch()
        notes = []
        captures = []
        stats = nil
        state = .error(reason)
    }

    // MARK: - Mutations

    @discardableResult
    func create(_ input: ClawJSMemoryClient.CreateNoteInput) async throws -> ClawJSMemoryClient.CreateNoteResponse {
        let response = try await client.createNote(input)
        await refresh()
        return response
    }

    @discardableResult
    func update(
        id: String,
        patch: ClawJSMemoryClient.UpdateNotePatch,
        editor: String = "user"
    ) async throws -> ClawJSMemoryClient.UpdateNoteResponse {
        let response = try await client.updateNote(id: id, patch: patch, editor: editor)
        await refresh()
        return response
    }

    @discardableResult
    func delete(id: String) async throws -> ClawJSMemoryClient.DeleteNoteResponse {
        let response = try await client.deleteNote(id: id)
        await refresh()
        return response
    }

    @discardableResult
    func promote(captureId: String) async throws -> ClawJSMemoryClient.PromoteResponse {
        let response = try await client.promoteCapture(id: captureId)
        await refresh()
        return response
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
}
