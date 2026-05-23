import Foundation
import Combine

/// Single source of truth for the MCP page. The UI talks to ClawJS over
/// the stable `claw mcp ... --json` adapter; Clawix never parses or
/// mutates Codex-owned TOML directly.
@MainActor
final class MCPServersStore: ObservableObject {
    static let shared = MCPServersStore()

    @Published private(set) var servers: [MCPServerConfig] = []
    @Published private(set) var lastError: String? = nil
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false

    private let persistence: MCPServersPersistence
    private var loadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var saveGeneration = 0

    convenience init() {
        self.init(persistence: ClawJSMCPClient())
    }

    init(persistence: MCPServersPersistence, autoLoad: Bool = true) {
        self.persistence = persistence
        if autoLoad {
            reload()
        }
    }

    deinit {
        loadTask?.cancel()
        saveTask?.cancel()
    }

    // MARK: - Mutations

    func reload() {
        _ = startReload()
    }

    func refresh() async {
        await startReload().value
    }

    func cancelSurfaceWork() {
        loadGeneration += 1
        saveGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        saveTask?.cancel()
        saveTask = nil
        isLoading = false
        isSaving = false
    }

    @discardableResult
    private func startReload() -> Task<Void, Never> {
        loadGeneration += 1
        let generation = loadGeneration
        loadTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runReload(generation: generation)
        }
        loadTask = task
        return task
    }

    private func runReload(generation: Int) async {
        guard generation == loadGeneration else { return }
        isLoading = true
        do {
            let loaded = try await persistence.loadServers()
            try Task.checkCancellation()
            guard generation == loadGeneration else { return }
            servers = loaded
            lastError = nil
            finishLoadIfCurrent(generation)
        } catch is CancellationError {
            finishLoadIfCurrent(generation)
        } catch {
            guard generation == loadGeneration else { return }
            lastError = userFacingError(error, surface: "settings.mcp.reload")
            finishLoadIfCurrent(generation)
        }
    }

    func toggleEnabled(_ server: MCPServerConfig, isOn: Bool) {
        guard let idx = servers.firstIndex(of: server) else { return }
        servers[idx].enabled = isOn
        persistCurrentServers()
    }

    /// Inserts a new server or updates an existing one identified by
    /// `id`. Returns the canonical `tomlIdentifier` that ended up on
    /// disk, useful when callers need to navigate to it afterwards.
    @discardableResult
    func upsert(_ server: MCPServerConfig) -> String {
        let trimmed = server.sanitised()
        if let idx = servers.firstIndex(where: { $0.id == trimmed.id }) {
            servers[idx] = trimmed
        } else {
            servers.append(trimmed)
        }
        persistCurrentServers()
        return trimmed.tomlIdentifier
    }

    func delete(_ server: MCPServerConfig) {
        servers.removeAll { $0.id == server.id }
        persistCurrentServers()
    }

    // MARK: - Persistence

    private func persistCurrentServers() {
        saveGeneration += 1
        let generation = saveGeneration
        let snapshot = servers
        saveTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.persist(snapshot, generation: generation)
        }
        saveTask = task
    }

    private func persist(_ snapshot: [MCPServerConfig], generation: Int) async {
        guard generation == saveGeneration else { return }
        isSaving = true
        do {
            try await persistence.saveServers(snapshot)
            try Task.checkCancellation()
            guard generation == saveGeneration else { return }
            lastError = nil
            finishSaveIfCurrent(generation)
        } catch is CancellationError {
            finishSaveIfCurrent(generation)
        } catch {
            guard generation == saveGeneration else { return }
            lastError = userFacingError(error, surface: "settings.mcp.save")
            finishSaveIfCurrent(generation)
        }
    }

    private func finishLoadIfCurrent(_ generation: Int) {
        guard generation == loadGeneration else { return }
        isLoading = false
        loadTask = nil
    }

    private func finishSaveIfCurrent(_ generation: Int) {
        guard generation == saveGeneration else { return }
        isSaving = false
        saveTask = nil
    }

    private func userFacingError(_ error: Error, surface: String) -> String {
        let failure = UserFacingFailure.classify(error.localizedDescription)
        failure.log(surface: surface)
        return failure.displayMessage
    }
}
