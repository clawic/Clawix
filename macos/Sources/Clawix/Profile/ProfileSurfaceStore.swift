import Combine
import Foundation

/// @MainActor orchestrator for the Profile / Feed / Chats / Marketplace
/// surfaces. Owns the HTTP client, publishes state for SwiftUI views, and
/// schedules background refreshes.
@MainActor
final class ProfileSurfaceStore: ObservableObject {
    typealias TokenOperation = @MainActor () -> String?

    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case error(String)
    }

    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var me: ClawJSProfileClient.Profile?
    @Published private(set) var ownBlocks: [ClawJSProfileClient.Block] = []
    @Published private(set) var groups: [ClawJSProfileClient.Group] = []
    @Published private(set) var peers: [ClawJSProfileClient.PeerDirectoryEntry] = []
    @Published private(set) var feedEntries: [ClawJSProfileClient.FeedEntry] = []
    @Published private(set) var chatThreads: [ClawJSProfileClient.ChatThread] = []
    @Published private(set) var chatMessagesByPeer: [String: [ClawJSProfileClient.ChatMessage]] = [:]
    @Published private(set) var marketplaceIntents: [ClawJSProfileClient.DiscoveredIntent] = []

    @Published var selectedVertical: String?
    @Published var selectedGroupId: String?
    @Published var feedKeywords: String = ""

    private var client: any ClawJSProfileClienting
    private let tokenOperation: TokenOperation
    private var bootstrapTask: Task<Void, Never>?
    private var bootstrapGeneration = 0
    private var feedRefreshTask: Task<Void, Never>?
    private var feedRefreshGeneration = 0
    private var chatsRefreshTask: Task<Void, Never>?
    private var chatsRefreshGeneration = 0
    private var messageLoadTasks: [String: Task<[ClawJSProfileClient.ChatMessage], Error>] = [:]
    private var messageLoadGenerations: [String: Int] = [:]
    private var messageSendTasks: [UUID: Task<ClawJSProfileClient.ChatMessage, Error>] = [:]
    private var messageSendGeneration = 0
    private var marketplaceRefreshTask: Task<Void, Never>?
    private var marketplaceRefreshGeneration = 0

    init(
        client: (any ClawJSProfileClienting)? = nil,
        tokenOperation: TokenOperation? = nil
    ) {
        self.tokenOperation = tokenOperation ?? {
            ClawJSServiceManager.shared.adminTokenIfSpawned(for: .index)
                ?? (try? ClawJSServiceManager.adminTokenFromTokenFile(for: .index))
        }
        if let client {
            self.client = client
        } else {
            let index = ClawJSIndexClient(bearerToken: self.tokenOperation())
            self.client = ClawJSProfileClient(indexClient: index)
        }
    }

    deinit {
        bootstrapTask?.cancel()
        feedRefreshTask?.cancel()
        chatsRefreshTask?.cancel()
        messageLoadTasks.values.forEach { $0.cancel() }
        messageSendTasks.values.forEach { $0.cancel() }
        marketplaceRefreshTask?.cancel()
    }

    func ensureToken() {
        if client.indexBearerToken == nil {
            client.indexBearerToken = tokenOperation()
        }
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        let generation = nextBootstrapGeneration()
        bootstrapTask?.cancel()
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.runBootstrap(generation: generation)
        }
        bootstrapTask = task
        await task.value
    }

    private func runBootstrap(generation: Int) async {
        ensureToken()
        loadState = .loading
        do {
            async let me = client.me()
            async let groups = client.listGroups()
            async let blocks = client.listBlocks(vertical: nil)
            async let peers = client.listPeers()
            async let feed = client.listFeed(vertical: nil, groupId: nil, keywords: nil, limit: 100)
            async let chats = client.listChats()
            async let intents = client.discoveredIntents(vertical: nil, geoZone: nil, tag: nil, priceBand: nil, limit: 100)
            let loadedMe = try await me
            let loadedGroups = try await groups
            let loadedBlocks = try await blocks
            let loadedPeers = try await peers
            let loadedFeed = try await feed
            let loadedChats = try await chats
            let loadedIntents = try await intents
            try Task.checkCancellation()
            guard isCurrentBootstrap(generation) else { return }
            self.me = loadedMe
            self.groups = loadedGroups
            self.ownBlocks = loadedBlocks
            self.peers = loadedPeers
            self.feedEntries = loadedFeed
            self.chatThreads = loadedChats
            self.marketplaceIntents = loadedIntents
            loadState = .ready
        } catch is CancellationError {
        } catch {
            guard isCurrentBootstrap(generation) else { return }
            loadState = .error(error.localizedDescription)
        }
        finishBootstrapIfCurrent(generation)
    }

    func refreshFeed() async {
        let generation = nextFeedRefreshGeneration()
        let vertical = selectedVertical
        let groupId = selectedGroupId
        let keywords = feedKeywords.isEmpty ? nil : feedKeywords
        feedRefreshTask?.cancel()
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.runFeedRefresh(
                generation: generation,
                vertical: vertical,
                groupId: groupId,
                keywords: keywords
            )
        }
        feedRefreshTask = task
        await task.value
    }

    private func runFeedRefresh(generation: Int, vertical: String?, groupId: String?, keywords: String?) async {
        ensureToken()
        do {
            let entries = try await client.listFeed(
                vertical: vertical,
                groupId: groupId,
                keywords: keywords,
                limit: 100,
            )
            try Task.checkCancellation()
            guard isCurrentFeedRefresh(generation) else { return }
            self.feedEntries = entries
        } catch is CancellationError {
        } catch {
            guard isCurrentFeedRefresh(generation) else { return }
            loadState = .error(error.localizedDescription)
        }
        finishFeedRefreshIfCurrent(generation)
    }

    func refreshChats() async {
        let generation = nextChatsRefreshGeneration()
        chatsRefreshTask?.cancel()
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.runChatsRefresh(generation: generation)
        }
        chatsRefreshTask = task
        await task.value
    }

    private func runChatsRefresh(generation: Int) async {
        ensureToken()
        do {
            let threads = try await client.listChats()
            try Task.checkCancellation()
            guard isCurrentChatsRefresh(generation) else { return }
            self.chatThreads = threads
        } catch is CancellationError {
        } catch {
            guard isCurrentChatsRefresh(generation) else { return }
            loadState = .error(error.localizedDescription)
        }
        finishChatsRefreshIfCurrent(generation)
    }

    func refreshMarketplace() async {
        let generation = nextMarketplaceRefreshGeneration()
        let vertical = selectedVertical
        marketplaceRefreshTask?.cancel()
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.runMarketplaceRefresh(generation: generation, vertical: vertical)
        }
        marketplaceRefreshTask = task
        await task.value
    }

    private func runMarketplaceRefresh(generation: Int, vertical: String?) async {
        ensureToken()
        do {
            let intents = try await client.discoveredIntents(
                vertical: vertical, geoZone: nil, tag: nil, priceBand: nil, limit: 100,
            )
            try Task.checkCancellation()
            guard isCurrentMarketplaceRefresh(generation) else { return }
            self.marketplaceIntents = intents
        } catch is CancellationError {
        } catch {
            guard isCurrentMarketplaceRefresh(generation) else { return }
            loadState = .error(error.localizedDescription)
        }
        finishMarketplaceRefreshIfCurrent(generation)
    }

    func cancelSurfaceWork() {
        bootstrapGeneration += 1
        bootstrapTask?.cancel()
        bootstrapTask = nil
        feedRefreshGeneration += 1
        feedRefreshTask?.cancel()
        feedRefreshTask = nil
        chatsRefreshGeneration += 1
        chatsRefreshTask?.cancel()
        chatsRefreshTask = nil
        cancelMessageLoadTasks()
        cancelMessageSendTasks()
        marketplaceRefreshGeneration += 1
        marketplaceRefreshTask?.cancel()
        marketplaceRefreshTask = nil
    }

    func cancelChatSurfaceWork() {
        chatsRefreshGeneration += 1
        chatsRefreshTask?.cancel()
        chatsRefreshTask = nil
        cancelMessageLoadTasks()
        cancelMessageSendTasks()
    }

    func cancelFeedSurfaceWork() {
        bootstrapGeneration += 1
        bootstrapTask?.cancel()
        bootstrapTask = nil
        feedRefreshGeneration += 1
        feedRefreshTask?.cancel()
        feedRefreshTask = nil
    }

    // MARK: - Mutations

    func initProfile(alias: String, mnemonic: String?) async throws -> ClawJSProfileClient.InitResponse {
        ensureToken()
        let resp = try await client.initProfile(alias: alias, mnemonic: mnemonic, passphrase: nil)
        self.me = resp.profile
        return resp
    }

    func renameHandle(to alias: String) async throws {
        ensureToken()
        let updated = try await client.setHandle(alias: alias)
        self.me = updated
    }

    func createBlock(_ input: ClawJSProfileClient.CreateBlockInput) async throws {
        ensureToken()
        let block = try await client.createBlock(input)
        self.ownBlocks.insert(block, at: 0)
    }

    func deleteBlock(_ blockId: String) async throws {
        ensureToken()
        try await client.deleteBlock(blockId)
        self.ownBlocks.removeAll { $0.blockId == blockId }
    }

    func createGroup(id: String, label: String? = nil) async throws {
        ensureToken()
        let g = try await client.createGroup(id: id, label: label)
        self.groups.append(g)
    }

    func addMember(groupId: String, rootPubkeyHex: String) async throws {
        ensureToken()
        let updated = try await client.addMember(groupId: groupId, rootPubkeyHex: rootPubkeyHex)
        if let idx = groups.firstIndex(where: { $0.id == updated.id }) {
            groups[idx] = updated
        }
    }

    func pair(link: String) async throws -> ClawJSProfileClient.Handle {
        ensureToken()
        let handle = try await client.pairByFingerprint(pairingLink: link)
        // Refresh the directory so the new peer is visible immediately.
        self.peers = (try? await client.listPeers()) ?? self.peers
        return handle
    }

    func issueCapability(blockId: String, level: String, ttlSeconds: Int? = nil) async throws -> ClawJSProfileClient.Capability {
        ensureToken()
        return try await client.issueCapability(blockId: blockId, level: level, issuedToHex: nil, ttlSeconds: ttlSeconds)
    }

    func sendMessage(peer: String, body: String) async throws -> ClawJSProfileClient.ChatMessage {
        let generation = currentMessageSendGeneration()
        let taskId = UUID()
        let task = Task<ClawJSProfileClient.ChatMessage, Error> { @MainActor [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.runMessageSend(
                peer: peer,
                body: body,
                generation: generation
            )
        }
        messageSendTasks[taskId] = task
        do {
            let message = try await task.value
            finishMessageSend(taskId: taskId)
            return message
        } catch {
            finishMessageSend(taskId: taskId)
            throw error
        }
    }

    func messages(forPeer peer: String) -> [ClawJSProfileClient.ChatMessage] {
        chatMessagesByPeer[peer] ?? []
    }

    func loadMessages(peer: String) async throws -> [ClawJSProfileClient.ChatMessage] {
        let generation = nextMessageLoadGeneration(for: peer)
        messageLoadTasks[peer]?.cancel()
        let task = Task<[ClawJSProfileClient.ChatMessage], Error> { @MainActor [weak self] in
            guard let self else { return [] }
            return try await self.runMessageLoad(peer: peer, generation: generation)
        }
        messageLoadTasks[peer] = task
        do {
            let messages = try await task.value
            finishMessageLoadIfCurrent(peer: peer, generation: generation)
            return messages
        } catch {
            finishMessageLoadIfCurrent(peer: peer, generation: generation)
            throw error
        }
    }

    private func runMessageLoad(peer: String, generation: Int) async throws -> [ClawJSProfileClient.ChatMessage] {
        ensureToken()
        let messages = try await client.listMessages(peer: peer, limit: 100, before: nil)
        try Task.checkCancellation()
        guard isCurrentMessageLoad(peer: peer, generation: generation) else { throw CancellationError() }
        chatMessagesByPeer[peer] = messages
        return messages
    }

    private func runMessageSend(peer: String, body: String, generation: Int) async throws -> ClawJSProfileClient.ChatMessage {
        ensureToken()
        let message = try await client.sendMessage(peer: peer, body: body)
        try Task.checkCancellation()
        guard isCurrentMessageSend(generation) else { throw CancellationError() }
        chatMessagesByPeer[peer, default: []].append(message)
        return message
    }

    func expressInterest(intentId: String) async throws -> ClawJSProfileClient.ExpressInterestResult {
        ensureToken()
        return try await client.expressInterest(intentId: intentId, template: nil)
    }

    private func nextBootstrapGeneration() -> Int {
        bootstrapGeneration += 1
        return bootstrapGeneration
    }

    private func isCurrentBootstrap(_ generation: Int) -> Bool {
        bootstrapGeneration == generation
    }

    private func finishBootstrapIfCurrent(_ generation: Int) {
        guard isCurrentBootstrap(generation) else { return }
        bootstrapTask = nil
    }

    private func nextFeedRefreshGeneration() -> Int {
        feedRefreshGeneration += 1
        return feedRefreshGeneration
    }

    private func isCurrentFeedRefresh(_ generation: Int) -> Bool {
        feedRefreshGeneration == generation
    }

    private func finishFeedRefreshIfCurrent(_ generation: Int) {
        guard isCurrentFeedRefresh(generation) else { return }
        feedRefreshTask = nil
    }

    private func nextChatsRefreshGeneration() -> Int {
        chatsRefreshGeneration += 1
        return chatsRefreshGeneration
    }

    private func isCurrentChatsRefresh(_ generation: Int) -> Bool {
        chatsRefreshGeneration == generation
    }

    private func finishChatsRefreshIfCurrent(_ generation: Int) {
        guard isCurrentChatsRefresh(generation) else { return }
        chatsRefreshTask = nil
    }

    private func nextMessageLoadGeneration(for peer: String) -> Int {
        let generation = (messageLoadGenerations[peer] ?? 0) + 1
        messageLoadGenerations[peer] = generation
        return generation
    }

    private func isCurrentMessageLoad(peer: String, generation: Int) -> Bool {
        messageLoadGenerations[peer] == generation
    }

    private func finishMessageLoadIfCurrent(peer: String, generation: Int) {
        guard isCurrentMessageLoad(peer: peer, generation: generation) else { return }
        messageLoadTasks[peer] = nil
    }

    private func cancelMessageLoadTasks() {
        for peer in messageLoadTasks.keys {
            messageLoadGenerations[peer, default: 0] += 1
        }
        messageLoadTasks.values.forEach { $0.cancel() }
        messageLoadTasks.removeAll()
    }

    private func currentMessageSendGeneration() -> Int {
        messageSendGeneration
    }

    private func isCurrentMessageSend(_ generation: Int) -> Bool {
        messageSendGeneration == generation
    }

    private func finishMessageSend(taskId: UUID) {
        messageSendTasks[taskId] = nil
    }

    private func cancelMessageSendTasks() {
        messageSendGeneration += 1
        messageSendTasks.values.forEach { $0.cancel() }
        messageSendTasks.removeAll()
    }

    private func nextMarketplaceRefreshGeneration() -> Int {
        marketplaceRefreshGeneration += 1
        return marketplaceRefreshGeneration
    }

    private func isCurrentMarketplaceRefresh(_ generation: Int) -> Bool {
        marketplaceRefreshGeneration == generation
    }

    private func finishMarketplaceRefreshIfCurrent(_ generation: Int) {
        guard isCurrentMarketplaceRefresh(generation) else { return }
        marketplaceRefreshTask = nil
    }
}
