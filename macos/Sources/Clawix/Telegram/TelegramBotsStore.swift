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
    typealias SetWebhookOperation = @MainActor (_ bot: TelegramBot, _ url: String, _ secretToken: String?) async throws -> ClawCliResult
    typealias SaveCommandsOperation = @MainActor (_ bot: TelegramBot, _ commands: [TelegramCommandSpec]) async throws -> ClawCliResult
    typealias SendMessageOperation = @MainActor (_ bot: TelegramBot, _ chatId: String, _ text: String, _ parseMode: String?) async throws -> ClawCliResult

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
    private let startPollingOperation: BotEnvelopeOperation
    private let stopPollingOperation: BotEnvelopeOperation
    private let setWebhookOperation: SetWebhookOperation
    private let clearWebhookOperation: BotEnvelopeOperation
    private let saveCommandsOperation: SaveCommandsOperation
    private let sendMessageOperation: SendMessageOperation
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var reloadTasks: [ReloadKey: Task<Void, Never>] = [:]
    private var reloadGenerations: [ReloadKey: Int] = [:]
    private var actionTasks: [String: Task<Bool, Never>] = [:]
    private var actionGenerations: [String: Int] = [:]

    init(
        client: TelegramServiceClient = TelegramServiceClient(),
        listBotsOperation: ListBotsOperation? = nil,
        reloadCommandsOperation: BotEnvelopeOperation? = nil,
        reloadChatsOperation: BotChatsOperation? = nil,
        startPollingOperation: BotEnvelopeOperation? = nil,
        stopPollingOperation: BotEnvelopeOperation? = nil,
        setWebhookOperation: SetWebhookOperation? = nil,
        clearWebhookOperation: BotEnvelopeOperation? = nil,
        saveCommandsOperation: SaveCommandsOperation? = nil,
        sendMessageOperation: SendMessageOperation? = nil
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
        self.startPollingOperation = startPollingOperation ?? { bot in
            try await client.startPolling(botId: bot.id)
        }
        self.stopPollingOperation = stopPollingOperation ?? { bot in
            try await client.stopPolling(botId: bot.id)
        }
        self.setWebhookOperation = setWebhookOperation ?? { bot, url, secretToken in
            try await client.setWebhook(botId: bot.id, url: url, secretToken: secretToken)
        }
        self.clearWebhookOperation = clearWebhookOperation ?? { bot in
            try await client.clearWebhook(botId: bot.id)
        }
        self.saveCommandsOperation = saveCommandsOperation ?? { bot, commands in
            try await client.setCommands(botId: bot.id, commands: commands)
        }
        self.sendMessageOperation = sendMessageOperation ?? { bot, chatId, text, parseMode in
            try await client.sendMessage(
                botId: bot.id,
                chatId: chatId,
                body: .text(text),
                parseMode: parseMode
            )
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
        await runAction(bot: bot) { try await self.startPollingOperation(bot) }
    }

    func stopPolling(_ bot: TelegramBot) async {
        await runAction(bot: bot) { try await self.stopPollingOperation(bot) }
    }

    func setWebhook(_ bot: TelegramBot, url: String, secretToken: String?) async {
        await runAction(bot: bot) {
            try await self.setWebhookOperation(bot, url, secretToken)
        }
    }

    func clearWebhook(_ bot: TelegramBot) async {
        await runAction(bot: bot) { try await self.clearWebhookOperation(bot) }
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
        let completed = await runAction(bot: bot) {
            try await self.saveCommandsOperation(bot, commands)
        }
        if completed {
            await reloadCommands(bot)
        }
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
            try await self.sendMessageOperation(bot, chatId, text, parseMode)
        }
    }

    // MARK: - Internal

    @discardableResult
    private func runAction(
        bot: TelegramBot,
        _ work: @escaping @MainActor () async throws -> ClawCliResult
    ) async -> Bool {
        let generation = nextActionGeneration(for: bot.id)
        actionTasks[bot.id]?.cancel()
        let task = Task<Bool, Never> { @MainActor [weak self] in
            guard let self else { return false }
            return await self.runActionTask(bot: bot, generation: generation, work)
        }
        actionTasks[bot.id] = task
        return await task.value
    }

    private func runActionTask(
        bot: TelegramBot,
        generation: Int,
        _ work: @escaping @MainActor () async throws -> ClawCliResult
    ) async -> Bool {
        inflight.insert(bot.id)
        do {
            let envelope = try await work()
            try Task.checkCancellation()
            guard isCurrentAction(botId: bot.id, generation: generation) else { return false }
            lastActionResult[bot.id] = envelope
        } catch is CancellationError {
            return false
        } catch {
            guard isCurrentAction(botId: bot.id, generation: generation) else { return false }
            lastActionResult[bot.id] = ClawCliResult(
                ok: false,
                exitCode: nil,
                stdout: "",
                stderr: error.localizedDescription,
                json: nil
            )
        }
        guard isCurrentAction(botId: bot.id, generation: generation) else { return false }
        await refresh()
        if isCurrentAction(botId: bot.id, generation: generation) {
            actionTasks[bot.id] = nil
            inflight.remove(bot.id)
            return true
        }
        return false
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

    private func nextActionGeneration(for botId: String) -> Int {
        let generation = (actionGenerations[botId] ?? 0) + 1
        actionGenerations[botId] = generation
        return generation
    }

    private func isCurrentAction(botId: String, generation: Int) -> Bool {
        actionGenerations[botId] == generation
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
