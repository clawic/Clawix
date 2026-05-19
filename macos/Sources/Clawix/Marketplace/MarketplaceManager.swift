import Combine
import Foundation

/// State orchestrator for the marketplace tab. Owns the marketplace/1.0.0 client and
/// publishes the data the SwiftUI views render.
@MainActor
final class MarketplaceManager: ObservableObject {
    typealias TokenOperation = @MainActor () -> String?

    enum State: Equatable {
        case idle
        case loading
        case ready
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var roots: [ClawJSMarketplaceClient.RootKey] = []
    @Published private(set) var devices: [ClawJSMarketplaceClient.DeviceKey] = []
    @Published private(set) var roles: [ClawJSMarketplaceClient.RoleKey] = []
    @Published private(set) var myOffers: [ClawJSMarketplaceClient.Intent] = []
    @Published private(set) var myWants: [ClawJSMarketplaceClient.Intent] = []
    @Published private(set) var observedIntents: [ClawJSMarketplaceClient.Intent] = []
    @Published private(set) var nativeIntentsFromPeers: [ClawJSMarketplaceClient.Intent] = []
    @Published private(set) var receipts: [ClawJSMarketplaceClient.MatchReceipt] = []
    @Published private(set) var inbound: [ClawJSMarketplaceClient.InboundMessage] = []
    @Published private(set) var peerLevels: [ClawJSMarketplaceClient.PeerLevel] = []
    @Published private(set) var brokers: [ClawJSMarketplaceClient.Broker] = []
    @Published var selectedVertical: String? = nil

    private var marketplace: any ClawJSMarketplaceClienting
    private let tokenOperation: TokenOperation
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0

    init(
        client: (any ClawJSMarketplaceClienting)? = nil,
        tokenOperation: TokenOperation? = nil
    ) {
        self.tokenOperation = tokenOperation ?? {
            ClawJSServiceManager.shared.adminTokenIfSpawned(for: .index)
                ?? (try? ClawJSServiceManager.adminTokenFromTokenFile(for: .index))
        }
        if let client {
            self.marketplace = client
        } else {
            let index = ClawJSIndexClient(bearerToken: self.tokenOperation())
            self.marketplace = ClawJSMarketplaceClient(indexClient: index)
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    func ensureToken() {
        if marketplace.indexBearerToken == nil {
            marketplace.indexBearerToken = tokenOperation()
        }
    }

    func refresh() async {
        let generation = nextRefreshGeneration()
        refreshTask?.cancel()
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.runRefresh(generation: generation)
        }
        refreshTask = task
        await task.value
    }

    private func runRefresh(generation: Int) async {
        ensureToken()
        state = .loading
        do {
            async let rootsTask = marketplace.listRoots()
            async let devicesTask = marketplace.listDevices(rootKeyId: nil)
            async let rolesTask = marketplace.listRoles(rootKeyId: nil, vertical: nil)
            async let nativeOffersTask = marketplace.listIntents(filter: .init(side: "offer", provenance: "native"))
            async let nativeWantsTask = marketplace.listIntents(filter: .init(side: "want", provenance: "native"))
            async let observedTask = marketplace.listIntents(filter: .init(provenance: "observed"))
            async let receiptsTask = marketplace.listMatchReceipts(myRoleKeyId: nil, status: nil)
            async let inboundTask = marketplace.listInbound(recipientRoleKeyId: nil)
            async let peerLevelsTask = marketplace.listPeerLevels(myRoleKeyId: nil)
            async let brokersTask = marketplace.listBrokers(vertical: nil)

            let (roots, devices, roles, nativeOffers, nativeWants, observed, receipts, inbound, peers, brokers) = try await (
                rootsTask, devicesTask, rolesTask,
                nativeOffersTask, nativeWantsTask, observedTask,
                receiptsTask, inboundTask, peerLevelsTask, brokersTask
            )

            try Task.checkCancellation()
            guard isCurrentRefresh(generation) else { return }
            self.roots = roots
            self.devices = devices
            self.roles = roles
            // Native intents whose `roleKeyId` matches a local role are mine; others are peers'.
            let localRoleIds = Set(roles.map(\.id))
            self.myOffers = nativeOffers.filter { roleKeyId in
                localRoleIds.contains(roleKeyId.roleKeyId ?? "")
            }
            self.myWants = nativeWants.filter { roleKeyId in
                localRoleIds.contains(roleKeyId.roleKeyId ?? "")
            }
            let peerNatives = (nativeOffers + nativeWants).filter { intent in
                guard let rid = intent.roleKeyId else { return true }
                return !localRoleIds.contains(rid)
            }
            self.nativeIntentsFromPeers = peerNatives
            self.observedIntents = observed
            self.receipts = receipts
            self.inbound = inbound
            self.peerLevels = peers
            self.brokers = brokers
            state = .ready
        } catch is CancellationError {
        } catch {
            guard isCurrentRefresh(generation) else { return }
            state = .error(error.localizedDescription)
        }
        finishRefreshIfCurrent(generation)
    }

    func cancelSurfaceWork() {
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
    }

    func markRead(messageId: String) async {
        ensureToken()
        do {
            try await marketplace.markRead(messageId: messageId)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func updateIntentStatus(id: String, status: String) async {
        ensureToken()
        do {
            try await marketplace.updateIntentStatus(id: id, status: status)
        } catch {
            state = .error(error.localizedDescription)
            return
        }
        await refresh()
    }

    private func nextRefreshGeneration() -> Int {
        refreshGeneration += 1
        return refreshGeneration
    }

    private func isCurrentRefresh(_ generation: Int) -> Bool {
        refreshGeneration == generation
    }

    private func finishRefreshIfCurrent(_ generation: Int) {
        guard isCurrentRefresh(generation) else { return }
        refreshTask = nil
    }
}
