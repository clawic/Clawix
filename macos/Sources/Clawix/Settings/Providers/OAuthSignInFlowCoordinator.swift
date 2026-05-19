import AIProviders
import Foundation

@MainActor
final class OAuthSignInFlowCoordinator: ObservableObject {
    enum State: Equatable {
        case idle
        case running
        case done
        case failed(String)
    }

    struct Operations {
        let signIn: @MainActor (OAuthFlavor) async throws -> Void
        let cancel: @MainActor () -> Void

        @MainActor
        static func live() -> Operations {
            let coordinator = OAuthCoordinator()
            return Operations(
                signIn: { flavor in
                    _ = try await coordinator.signIn(flavor: flavor)
                },
                cancel: {
                    coordinator.cancel()
                }
            )
        }
    }

    @Published private(set) var state: State = .idle

    private let operations: Operations
    private var task: Task<Void, Never>?
    private var generation = 0

    init() {
        self.operations = .live()
    }

    init(operations: Operations) {
        self.operations = operations
    }

    deinit {
        task?.cancel()
    }

    func start(flavor: OAuthFlavor, onComplete: @escaping @MainActor () -> Void) {
        generation += 1
        let currentGeneration = generation
        task?.cancel()
        operations.cancel()
        state = .running
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await operations.signIn(flavor)
                try Task.checkCancellation()
                guard currentGeneration == generation else { return }
                state = .done
                task = nil
                onComplete()
            } catch is CancellationError {
                guard currentGeneration == generation else { return }
                state = .idle
                task = nil
            } catch let coordError as OAuthCoordinator.CoordinatorError {
                guard currentGeneration == generation else { return }
                state = .failed(coordError.errorDescription ?? "Sign-in failed.")
                task = nil
            } catch {
                guard currentGeneration == generation else { return }
                state = .failed(error.localizedDescription)
                task = nil
            }
        }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        operations.cancel()
        task = nil
        if state == .running {
            state = .idle
        }
    }
}
