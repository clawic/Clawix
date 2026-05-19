import Foundation
import Combine

/// Single source of truth for the "Local models" Settings page. Owns the
/// installer, the daemon, and the HTTP client, and exposes a flat
/// observable interface to the UI: which runtime version is installed,
/// whether the daemon is up, what models the user has, which is the
/// default, and what download is in flight.
///
/// All side-effecting actions are async functions; the UI binds to the
/// `@Published` properties and never reaches into the lower layers
/// directly.
@MainActor
final class LocalModelsService: ObservableObject {
    typealias PullOperation = @MainActor (String) -> AsyncThrowingStream<LocalModelsClient.PullEvent, Error>
    typealias RefreshModelListOperation = @MainActor () async -> Void

    static let shared = LocalModelsService()

    // MARK: - Published state

    @Published private(set) var runtimeState: LocalModelsRuntimeInstaller.State = .notInstalled
    @Published private(set) var daemonState: LocalModelsDaemon.State = .stopped

    /// Models the daemon reports as locally downloaded.
    @Published private(set) var installedModels: [LocalModelsClient.ModelTag] = []

    /// Models currently resident in VRAM (subset of `installedModels`).
    @Published private(set) var loadedModels: [LocalModelsClient.RunningModel] = []

    /// Per-model pull progress while a download is in flight. Keyed by
    /// the model name the user asked us to pull (e.g. "llama3.2:3b"); the
    /// daemon may stream multiple blob digests under the same pull, the
    /// service collapses them into a single 0..1 progress for the UI.
    @Published private(set) var downloads: [String: Download] = [:]

    /// Last non-download action failure, surfaced by the Models card.
    @Published private(set) var actionError: String?

    /// Daemon's reported version (the upstream tag), filled once the
    /// daemon is up. Used by the UI to surface "Runtime version: …".
    @Published private(set) var runtimeVersion: String?

    /// User's default model. Persisted in `UserDefaults` so it survives
    /// relaunches.
    @Published var defaultModel: String? {
        didSet {
            defaults.set(defaultModel, forKey: Self.defaultModelKey)
        }
    }

    /// `OLLAMA_KEEP_ALIVE` value. Persisted; applied at next daemon
    /// start. Format accepted by upstream: durations like "5m", "1h",
    /// "-1" (forever), "0" (immediate).
    @Published var keepAlive: String {
        didSet { defaults.set(keepAlive, forKey: Self.keepAliveKey) }
    }

    /// Default `num_ctx`. Persisted; applied at next daemon start.
    @Published var contextLength: Int {
        didSet { defaults.set(contextLength, forKey: Self.contextLengthKey) }
    }

    // MARK: - Persistence keys

    nonisolated static let defaultModelKey = "Clawix.LocalModels.defaultModel.v1"
    nonisolated static let keepAliveKey = "Clawix.LocalModels.keepAlive.v1"
    nonisolated static let contextLengthKey = "Clawix.LocalModels.numCtx.v1"

    // MARK: - Init

    private let installer = LocalModelsRuntimeInstaller.shared
    private let daemon = LocalModelsDaemon.shared
    private let client = LocalModelsClient.shared
    private let defaults: UserDefaults
    private let pullOperation: PullOperation
    private let refreshModelListOperation: RefreshModelListOperation?

    private var cancellables: Set<AnyCancellable> = []
    private var pollTask: Task<Void, Never>?
    private var pullTasks: [String: Task<Void, Never>] = [:]
    private var pullGenerations: [String: Int] = [:]

    init(
        defaults: UserDefaults = .standard,
        bindRuntimeState: Bool = true,
        pullOperation: PullOperation? = nil,
        refreshModelListOperation: RefreshModelListOperation? = nil
    ) {
        self.defaults = defaults
        self.pullOperation = pullOperation ?? { model in
            LocalModelsClient.shared.pull(model: model)
        }
        self.refreshModelListOperation = refreshModelListOperation
        self.defaultModel = defaults.string(forKey: Self.defaultModelKey)
        self.keepAlive = defaults.string(forKey: Self.keepAliveKey) ?? "5m"
        self.contextLength = defaults.integer(forKey: Self.contextLengthKey) > 0
            ? defaults.integer(forKey: Self.contextLengthKey)
            : 4_096

        guard bindRuntimeState else { return }

        // Mirror the lower-layer publishers so the UI only has to bind
        // to one ObservableObject.
        installer.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.runtimeState = $0 }
            .store(in: &cancellables)
        daemon.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.daemonState = $0
                if case .running = $0 { self?.beginPolling() }
                else { self?.endPolling() }
            }
            .store(in: &cancellables)

        installer.refresh()
    }

    // MARK: - Lifecycle actions

    /// One-shot "user toggled Enable local runtime ON". Walks the full
    /// chain: install if not present, start daemon, sync model list.
    /// Safe to call again; each step is idempotent.
    func enable() async {
        if !installer.isInstalled {
            await installer.install()
            // If install failed, the installer state will reflect it and
            // we don't proceed. The UI surfaces the error from
            // `runtimeState`.
            guard installer.isInstalled else { return }
        }
        await daemon.start(numCtx: contextLength, keepAlive: keepAlive)
        await refreshDaemonStatus()
    }

    /// "Toggle OFF". Stops the daemon. The runtime stays installed so a
    /// re-enable doesn't have to re-download.
    func disable() {
        cancelAllPulls()
        daemon.stop()
    }

    func cancelInstall() {
        installer.cancel()
    }

    // MARK: - Model actions

    func refreshModelList() async {
        if let refreshModelListOperation {
            await refreshModelListOperation()
            return
        }
        guard daemon.isRunning else { return }
        do {
            installedModels = try await client.tags()
            loadedModels = try await client.ps()
        } catch {
            // Soft-fail: leave the lists alone, the UI can show a stale
            // banner if desired.
        }
    }

    /// Streams a pull and updates `downloads[modelName]` as bytes flow.
    /// On success, refreshes the model list. On error, the entry is
    /// retained so the UI can show "failed, retry"; clear via
    /// `dismissDownloadError(for:)`.
    func pull(model: String) async {
        let generation = nextPullGeneration(for: model)
        pullTasks[model]?.cancel()
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.runPull(model: model, generation: generation)
        }
        pullTasks[model] = task
        await task.value
    }

    func cancelPull(model: String) {
        bumpPullGeneration(for: model)
        pullTasks[model]?.cancel()
        pullTasks[model] = nil
        if case .running = downloads[model]?.state {
            downloads[model] = nil
        }
    }

    func cancelAllPulls() {
        for model in Array(pullTasks.keys) {
            cancelPull(model: model)
        }
    }

    private func runPull(model: String, generation: Int) async {
        downloads[model] = Download(
            model: model,
            state: .running(progress: 0, status: "starting…")
        )
        do {
            for try await event in pullOperation(model) {
                try Task.checkCancellation()
                guard isCurrentPull(model: model, generation: generation) else { return }
                let total = event.total ?? 1
                let completed = event.completed ?? 0
                let progress = total > 0 ? Double(completed) / Double(total) : 0
                downloads[model] = Download(
                    model: model,
                    state: .running(progress: progress, status: event.status ?? "")
                )
            }
            try Task.checkCancellation()
            guard isCurrentPull(model: model, generation: generation) else { return }
            downloads[model] = nil
            await refreshModelList()
            if defaultModel == nil { defaultModel = model }
        } catch is CancellationError {
            guard isCurrentPull(model: model, generation: generation) else { return }
            downloads[model] = nil
        } catch {
            guard isCurrentPull(model: model, generation: generation) else { return }
            downloads[model] = Download(
                model: model,
                state: .failed(error.localizedDescription)
            )
        }
        if isCurrentPull(model: model, generation: generation) {
            pullTasks[model] = nil
        }
    }

    func dismissDownloadError(for model: String) {
        if case .failed = downloads[model]?.state {
            downloads[model] = nil
        }
    }

    func dismissActionError() {
        actionError = nil
    }

    func delete(model: String) async {
        guard daemon.isRunning else { return }
        do {
            try await client.delete(model: model)
            if defaultModel == model { defaultModel = nil }
            actionError = nil
            await refreshModelList()
        } catch {
            actionError = "Could not delete \(model): \(error.localizedDescription)"
        }
    }

    func unload(model: String) async {
        guard daemon.isRunning else { return }
        do {
            try await client.unload(model: model)
            actionError = nil
            await refreshModelList()
        } catch {
            actionError = "Could not unload \(model): \(error.localizedDescription)"
        }
    }

    func setDefault(model: String) {
        defaultModel = model
    }

    // MARK: - Polling

    private func beginPolling() {
        endPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshDaemonStatus()
                await self?.refreshModelList()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func endPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func refreshDaemonStatus() async {
        guard daemon.isRunning else { return }
        runtimeVersion = (try? await client.version())
    }

    private func nextPullGeneration(for model: String) -> Int {
        let generation = (pullGenerations[model] ?? 0) + 1
        pullGenerations[model] = generation
        return generation
    }

    private func bumpPullGeneration(for model: String) {
        pullGenerations[model] = (pullGenerations[model] ?? 0) + 1
    }

    private func isCurrentPull(model: String, generation: Int) -> Bool {
        pullGenerations[model] == generation
    }

    // MARK: - Wire types for the UI

    struct Download: Equatable {
        let model: String
        var state: DownloadState
    }

    enum DownloadState: Equatable {
        case running(progress: Double, status: String)
        case failed(String)
    }
}
