import Foundation
import SwiftUI

/// Observable wrapper around `TelegramServiceClient`. The Settings page
/// holds one as a `@StateObject` and binds its `bots` array to the
/// master pane. A 5s refresh task runs while the page is on screen and
/// is cancelled on disappear.
@MainActor
final class TelegramBotsStore: ObservableObject {
    typealias ListBotsOperation = @MainActor () async throws -> [TelegramBot]
    typealias BotEnvelopeOperation = @MainActor (_ bot: TelegramBot) async throws -> ClawCliResult
    typealias BotChatsOperation = @MainActor (_ bot: TelegramBot, _ query: String?) async throws -> ClawCliResult

    @Published private(set) var bots: [TelegramBot] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    /// Per-bot inflight markers so the UI can disable buttons while an
    /// action is running. Keyed by bot.id.
    @Published private(set) var inflight: Set<String> = []

    /// Per-bot last action result (envelope) so the UI can render
    /// stderr / stdout if a CLI call failed. Keyed by bot.id.
    @Published private(set) var lastActionResult: [String: ClawCliResult] = [:]

    /// Per-bot fetched chats. Populated lazily when the user opens the
    /// detail pane. Keyed by bot.id.
    @Published private(set) var chats: [String: [TelegramKnownChat]] = [:]

    /// Per-bot fetched commands. Populated lazily.
    @Published private(set) var commands: [String: [TelegramCommandSpec]] = [:]

    private let client: TelegramServiceClient
    private let listBotsOperation: ListBotsOperation
    private let reloadCommandsOperation: BotEnvelopeOperation
    private let reloadChatsOperation: BotChatsOperation
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var reloadTasks: [ReloadKey: Task<Void, Never>] = [:]
    private var reloadGenerations: [ReloadKey: Int] = [:]

    init(
        client: TelegramServiceClient = TelegramServiceClient(),
        listBotsOperation: ListBotsOperation? = nil,
        reloadCommandsOperation: BotEnvelopeOperation? = nil,
        reloadChatsOperation: BotChatsOperation? = nil
    ) {
        self.client = client
        self.listBotsOperation = listBotsOperation ?? {
            try await client.listBots()
        }
        self.reloadCommandsOperation = reloadCommandsOperation ?? { bot in
            try await client.getCommands(botId: bot.id)
        }
        self.reloadChatsOperation = reloadChatsOperation ?? { bot, query in
            try await client.listChats(botId: bot.id, query: query)
        }
    }

    // MARK: - Lifecycle

    func startRefreshing() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { return }
                await self.refresh()
            }
        }
    }

    func stopRefreshing() {
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        isLoading = false
        cancelAllReloads()
    }

    func resetForUnavailableService() {
        stopRefreshing()
        bots = []
        isLoading = false
        lastError = nil
    }

    // MARK: - Listing

    func refresh() async {
        let generation = nextRefreshGeneration()
        await runRefresh(generation: generation)
    }

    private func runRefresh(generation: Int) async {
        isLoading = true
        do {
            let next = try await listBotsOperation()
            try Task.checkCancellation()
            guard isCurrentRefresh(generation: generation) else { return }
            self.bots = next
            self.lastError = nil
            self.isLoading = false
        } catch is CancellationError {
            guard isCurrentRefresh(generation: generation) else { return }
            self.isLoading = false
        } catch {
            guard isCurrentRefresh(generation: generation) else { return }
            self.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            self.isLoading = false
        }
    }

    // MARK: - Actions

    @discardableResult
    func registerBot(
        secretName: String,
        accountId: String?,
        label: String?
    ) async -> Result<ClawCliResult, Swift.Error> {
        do {
            let result = try await client.registerBot(
                secretName: secretName,
                accountId: accountId,
                label: label
            )
            await refresh()
            return .success(result)
        } catch {
            return .failure(error)
        }
    }

    func startPolling(_ bot: TelegramBot) async {
        await runAction(bot: bot) { try await self.client.startPolling(botId: bot.id) }
    }

    func stopPolling(_ bot: TelegramBot) async {
        await runAction(bot: bot) { try await self.client.stopPolling(botId: bot.id) }
    }

    func setWebhook(_ bot: TelegramBot, url: String, secretToken: String?) async {
        await runAction(bot: bot) {
            try await self.client.setWebhook(
                botId: bot.id,
                url: url,
                secretToken: secretToken
            )
        }
    }

    func clearWebhook(_ bot: TelegramBot) async {
        await runAction(bot: bot) { try await self.client.clearWebhook(botId: bot.id) }
    }

    func reloadCommands(_ bot: TelegramBot) async {
        let key = ReloadKey(kind: .commands, botId: bot.id)
        let generation = nextReloadGeneration(for: key)
        reloadTasks[key]?.cancel()
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.runReloadCommands(bot, key: key, generation: generation)
        }
        reloadTasks[key] = task
        await task.value
    }

    private func runReloadCommands(_ bot: TelegramBot, key: ReloadKey, generation: Int) async {
        do {
            let envelope = try await reloadCommandsOperation(bot)
            try Task.checkCancellation()
            guard isCurrentReload(key: key, generation: generation) else { return }
            commands[bot.id] = TelegramCommandSpec.extract(from: envelope.json)
            lastActionResult[bot.id] = envelope
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentReload(key: key, generation: generation) else { return }
            lastActionResult[bot.id] = ClawCliResult(
                ok: false,
                exitCode: nil,
                stdout: "",
                stderr: error.localizedDescription,
                json: nil
            )
        }
        if isCurrentReload(key: key, generation: generation) {
            reloadTasks[key] = nil
        }
    }

    func saveCommands(_ bot: TelegramBot, commands: [TelegramCommandSpec]) async {
        await runAction(bot: bot) {
            try await self.client.setCommands(botId: bot.id, commands: commands)
        }
        await reloadCommands(bot)
    }

    func reloadChats(_ bot: TelegramBot, query: String? = nil) async {
        let key = ReloadKey(kind: .chats, botId: bot.id)
        let generation = nextReloadGeneration(for: key)
        reloadTasks[key]?.cancel()
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.runReloadChats(bot, query: query, key: key, generation: generation)
        }
        reloadTasks[key] = task
        await task.value
    }

    private func runReloadChats(
        _ bot: TelegramBot,
        query: String?,
        key: ReloadKey,
        generation: Int
    ) async {
        do {
            let envelope = try await reloadChatsOperation(bot, query)
            try Task.checkCancellation()
            guard isCurrentReload(key: key, generation: generation) else { return }
            chats[bot.id] = TelegramChatsExtractor.extract(from: envelope.json)
            lastActionResult[bot.id] = envelope
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentReload(key: key, generation: generation) else { return }
            lastActionResult[bot.id] = ClawCliResult(
                ok: false,
                exitCode: nil,
                stdout: "",
                stderr: error.localizedDescription,
                json: nil
            )
        }
        if isCurrentReload(key: key, generation: generation) {
            reloadTasks[key] = nil
        }
    }

    func sendMessage(
        _ bot: TelegramBot,
        chatId: String,
        text: String,
        parseMode: String? = nil
    ) async {
        await runAction(bot: bot) {
            try await self.client.sendMessage(
                botId: bot.id,
                chatId: chatId,
                body: .text(text),
                parseMode: parseMode
            )
        }
    }

    // MARK: - Internal

    private func runAction(
        bot: TelegramBot,
        _ work: @escaping () async throws -> ClawCliResult
    ) async {
        inflight.insert(bot.id)
        defer { inflight.remove(bot.id) }
        do {
            let envelope = try await work()
            lastActionResult[bot.id] = envelope
        } catch {
            lastActionResult[bot.id] = ClawCliResult(
                ok: false,
                exitCode: nil,
                stdout: "",
                stderr: error.localizedDescription,
                json: nil
            )
        }
        await refresh()
    }

    private func cancelAllReloads() {
        for key in Array(reloadTasks.keys) {
            bumpReloadGeneration(for: key)
            reloadTasks[key]?.cancel()
            reloadTasks[key] = nil
        }
    }

    private func nextRefreshGeneration() -> Int {
        refreshGeneration += 1
        return refreshGeneration
    }

    private func isCurrentRefresh(generation: Int) -> Bool {
        refreshGeneration == generation
    }

    private func nextReloadGeneration(for key: ReloadKey) -> Int {
        let generation = (reloadGenerations[key] ?? 0) + 1
        reloadGenerations[key] = generation
        return generation
    }

    private func bumpReloadGeneration(for key: ReloadKey) {
        reloadGenerations[key] = (reloadGenerations[key] ?? 0) + 1
    }

    private func isCurrentReload(key: ReloadKey, generation: Int) -> Bool {
        reloadGenerations[key] == generation
    }

    private enum ReloadKind: Hashable {
        case commands
        case chats
    }

    private struct ReloadKey: Hashable {
        let kind: ReloadKind
        let botId: String
    }
}
