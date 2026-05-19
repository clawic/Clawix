import Foundation

enum CancellableBackgroundTask {
    static func run<T: Sendable>(
        priority: TaskPriority = .utility,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        let task = Task.detached(priority: priority) {
            try await operation()
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
