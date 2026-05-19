import AIProviders
import AppKit
import Foundation

@MainActor
final class DeviceCodeSignInCoordinator: ObservableObject {
    enum Phase: Equatable {
        case requesting
        case waiting
        case done
    }

    struct Operations {
        let requestDeviceCode: @MainActor () async throws -> GitHubCopilotDeviceFlow.DeviceCode
        let openVerificationURL: @MainActor (URL) -> Void
        let pollAccessToken: @MainActor (_ deviceCode: String, _ interval: TimeInterval, _ expiresAt: Date) async throws -> String
        let persistAccount: @MainActor (_ accessToken: String, _ accountEmail: String?) throws -> Void
        let refreshStore: @MainActor () -> Void
        let completionDelay: @MainActor () async throws -> Void

        @MainActor
        static func live() -> Operations {
            let flow = GitHubCopilotDeviceFlow()
            return Operations(
                requestDeviceCode: {
                    try await flow.requestDeviceCode()
                },
                openVerificationURL: { url in
                    NSWorkspace.shared.open(url)
                },
                pollAccessToken: { deviceCode, interval, expiresAt in
                    try await flow.pollAccessToken(
                        deviceCode: deviceCode,
                        interval: interval,
                        expiresAt: expiresAt
                    )
                },
                persistAccount: { accessToken, accountEmail in
                    _ = try flow.persistAccount(githubAccessToken: accessToken, accountEmail: accountEmail)
                },
                refreshStore: {
                    AIAccountStoreObservable.shared.refresh()
                },
                completionDelay: {
                    try await Task.sleep(nanoseconds: 800_000_000)
                }
            )
        }
    }

    @Published private(set) var deviceCode: GitHubCopilotDeviceFlow.DeviceCode?
    @Published private(set) var error: String?
    @Published private(set) var phase: Phase = .requesting

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

    func start(onComplete: @escaping @MainActor () -> Void) {
        generation += 1
        let currentGeneration = generation
        task?.cancel()
        error = nil
        deviceCode = nil
        phase = .requesting
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let device = try await operations.requestDeviceCode()
                try Task.checkCancellation()
                guard currentGeneration == generation else { return }
                deviceCode = device
                phase = .waiting
                operations.openVerificationURL(device.verificationUri)
                let accessToken = try await operations.pollAccessToken(
                    device.deviceCode,
                    device.interval,
                    device.expiresAt
                )
                try Task.checkCancellation()
                guard currentGeneration == generation else { return }
                try operations.persistAccount(accessToken, nil)
                operations.refreshStore()
                phase = .done
                try await operations.completionDelay()
                try Task.checkCancellation()
                guard currentGeneration == generation else { return }
                task = nil
                onComplete()
            } catch is CancellationError {
                guard currentGeneration == generation else { return }
                task = nil
            } catch {
                guard currentGeneration == generation else { return }
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                task = nil
            }
        }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        error = nil
        deviceCode = nil
        phase = .requesting
    }
}
