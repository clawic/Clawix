import Combine
import Foundation

@MainActor
final class IndexEntityDetailStore: ObservableObject {
    @Published private(set) var currentEntityId: String?
    @Published private(set) var detail: ClawJSIndexClient.EntityDetailResponse?
    @Published private(set) var loadError: String?
    @Published private(set) var historyByField: [String: [ClawJSIndexClient.HistoryPoint]] = [:]

    private var detailTask: Task<Void, Never>?
    private var detailGeneration = 0
    private var historyTasks: [String: Task<Void, Never>] = [:]
    private var historyGenerations: [String: Int] = [:]

    deinit {
        detailTask?.cancel()
        for task in historyTasks.values {
            task.cancel()
        }
    }

    func load(entityId: String?, using store: IndexStore) async {
        guard let task = startDetailLoad(entityId: entityId, using: store) else { return }
        await task.value
    }

    func loadHistory(_ field: String, using store: IndexStore) async {
        guard let task = startHistoryLoad(field, using: store) else { return }
        await task.value
    }

    func history(for field: String) -> [ClawJSIndexClient.HistoryPoint] {
        historyByField[field] ?? []
    }

    func cancelSurfaceWork() {
        detailGeneration += 1
        detailTask?.cancel()
        detailTask = nil
        for field in Array(historyTasks.keys) {
            bumpHistoryGeneration(for: field)
            historyTasks[field]?.cancel()
            historyTasks[field] = nil
        }
    }

    @discardableResult
    private func startDetailLoad(
        entityId: String?,
        using store: IndexStore
    ) -> Task<Void, Never>? {
        detailGeneration += 1
        let generation = detailGeneration
        detailTask?.cancel()
        cancelHistoryLoads()
        guard let entityId else {
            currentEntityId = nil
            detail = nil
            loadError = nil
            historyByField = [:]
            detailTask = nil
            return nil
        }
        currentEntityId = entityId
        detail = nil
        loadError = nil
        historyByField = [:]
        let task = Task<Void, Never> { @MainActor [weak self, weak store] in
            guard let self, let store else { return }
            await self.runDetailLoad(entityId: entityId, using: store, generation: generation)
        }
        detailTask = task
        return task
    }

    private func runDetailLoad(
        entityId: String,
        using store: IndexStore,
        generation: Int
    ) async {
        do {
            let response = try await store.detail(for: entityId)
            try Task.checkCancellation()
            guard isCurrentDetail(entityId: entityId, generation: generation) else { return }
            detail = response
            loadError = nil
        } catch is CancellationError {
        } catch {
            guard isCurrentDetail(entityId: entityId, generation: generation) else { return }
            detail = nil
            loadError = Self.failureMessage(for: error, surface: "index.entityDetail.load")
        }
        finishDetailIfCurrent(entityId: entityId, generation: generation)
    }

    @discardableResult
    private func startHistoryLoad(
        _ field: String,
        using store: IndexStore
    ) -> Task<Void, Never>? {
        guard let entityId = currentEntityId else { return nil }
        if historyByField[field] != nil { return nil }
        let generation = nextHistoryGeneration(for: field)
        historyTasks[field]?.cancel()
        let task = Task<Void, Never> { @MainActor [weak self, weak store] in
            guard let self, let store else { return }
            await self.runHistoryLoad(
                entityId: entityId,
                field: field,
                using: store,
                generation: generation
            )
        }
        historyTasks[field] = task
        return task
    }

    private func runHistoryLoad(
        entityId: String,
        field: String,
        using store: IndexStore,
        generation: Int
    ) async {
        do {
            let points = try await store.history(for: entityId, field: field)
            try Task.checkCancellation()
            guard isCurrentHistory(entityId: entityId, field: field, generation: generation) else { return }
            historyByField[field] = points
        } catch is CancellationError {
        } catch {
            guard isCurrentHistory(entityId: entityId, field: field, generation: generation) else { return }
            _ = Self.failureMessage(for: error, surface: "index.entityDetail.history")
            historyByField[field] = []
        }
        finishHistoryIfCurrent(field: field, generation: generation)
    }

    private func cancelHistoryLoads() {
        for field in Array(historyTasks.keys) {
            bumpHistoryGeneration(for: field)
            historyTasks[field]?.cancel()
        }
        historyTasks.removeAll()
        historyByField = [:]
    }

    private func isCurrentDetail(entityId: String, generation: Int) -> Bool {
        currentEntityId == entityId && detailGeneration == generation
    }

    private func finishDetailIfCurrent(entityId: String, generation: Int) {
        guard isCurrentDetail(entityId: entityId, generation: generation) else { return }
        detailTask = nil
    }

    private func nextHistoryGeneration(for field: String) -> Int {
        let generation = (historyGenerations[field] ?? 0) + 1
        historyGenerations[field] = generation
        return generation
    }

    private func bumpHistoryGeneration(for field: String) {
        historyGenerations[field] = (historyGenerations[field] ?? 0) + 1
    }

    private func isCurrentHistory(entityId: String, field: String, generation: Int) -> Bool {
        currentEntityId == entityId && historyGenerations[field] == generation
    }

    private func finishHistoryIfCurrent(field: String, generation: Int) {
        guard historyGenerations[field] == generation else { return }
        historyTasks[field] = nil
    }

    private static func failureMessage(for error: Error, surface: String) -> String {
        let rawMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return UserFacingFailure.displayMessage(for: rawMessage, surface: surface)
    }
}
