import AIProviders
import Foundation

@MainActor
final class ProviderConnectionProbe: ObservableObject {
    enum State: Equatable {
        case idle
        case running
        case ok
        case failed(String)
    }

    typealias Operation = @MainActor (ProviderID, String, URL?) async throws -> Void

    @Published private(set) var state: State = .idle

    private let operation: Operation
    private var task: Task<Void, Never>?
    private var generation = 0

    init(operation: @escaping Operation = ProviderConnectionProbe.defaultOperation) {
        self.operation = operation
    }

    deinit {
        task?.cancel()
    }

    func run(providerId: ProviderID, apiKey: String, baseURL: URL?) {
        generation += 1
        let currentGeneration = generation
        task?.cancel()
        state = .running
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await operation(providerId, apiKey, baseURL)
                try Task.checkCancellation()
                guard currentGeneration == generation else { return }
                state = .ok
                task = nil
            } catch is CancellationError {
                guard currentGeneration == generation else { return }
                state = .idle
                task = nil
            } catch let error as AIClientError {
                guard currentGeneration == generation else { return }
                state = .failed(error.errorDescription ?? "Failed.")
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
        task = nil
        if state == .running {
            state = .idle
        }
    }

    private static func defaultOperation(providerId: ProviderID, apiKey: String, baseURL: URL?) async throws {
        let credentials = AIAccountCredentials(apiKey: apiKey)
        let model = ProviderCatalog.defaultModel(for: .chat, in: providerId)
            ?? ProviderCatalog.definition(for: providerId)?.models.first
        guard let model else {
            throw AIClientError.provider("No model available for this provider.")
        }
        let probeAccount = ProviderAccount(
            id: UUID(),
            providerId: providerId,
            label: "probe",
            authMethod: .apiKey,
            isEnabled: true,
            createdAt: Date(),
            baseURLOverride: baseURL
        )
        let client: any AIClient
        switch providerId {
        case .openai:
            client = OpenAIClient(account: probeAccount, model: model, credentials: credentials)
        case .anthropic:
            client = AnthropicClient(account: probeAccount, model: model, credentials: credentials)
        case .googleGemini:
            client = GoogleGeminiClient(account: probeAccount, model: model, credentials: credentials)
        case .ollama:
            client = OllamaClient(account: probeAccount, model: model, credentials: credentials)
        case .githubCopilot:
            throw AIClientError.provider("Use 'Sign in with GitHub' to test Copilot.")
        case .cursor:
            client = CursorClient(account: probeAccount, model: model, credentials: credentials)
        case .groq, .deepseek, .togetherAI, .glmZhipu, .xai, .mistral,
             .openrouter, .cerebras, .fireworks, .openAICompatibleCustom:
            client = OpenAICompatibleClient(account: probeAccount, model: model, credentials: credentials)
        }
        try await client.testConnection()
    }
}
