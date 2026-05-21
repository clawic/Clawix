import AIProviders
import Combine
import Foundation
import SwiftUI

/// Thin SwiftUI bridge over `AIAccountStore`. Re-publishes the latest
/// accounts list and exposes mutating helpers that refresh on success.
/// Backed by `AIAccountSecretsStore.shared` in production; tests inject
/// any `AIAccountStore`.
@MainActor
final class AIAccountStoreObservable: ObservableObject {
    typealias ListAccountsOperation = @MainActor () async throws -> [ProviderAccount]

    static let shared = AIAccountStoreObservable()

    @Published private(set) var accounts: [ProviderAccount] = []
    @Published var lastError: String?

    private let store: AIAccountStore
    private let listAccountsOperation: ListAccountsOperation
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0

    init(
        store: AIAccountStore = AIAccountSecretsStore.shared,
        refreshImmediately: Bool = true,
        listAccountsOperation: ListAccountsOperation? = nil
    ) {
        self.store = store
        self.listAccountsOperation = listAccountsOperation ?? {
            try await CancellableBackgroundTask.run(priority: .userInitiated) {
                try store.listAccounts()
            }
        }
        if refreshImmediately {
            refresh()
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    func refresh() {
        refreshGeneration += 1
        let currentGeneration = refreshGeneration
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let latestAccounts = try await listAccountsOperation()
                try Task.checkCancellation()
                guard currentGeneration == refreshGeneration else { return }
                accounts = latestAccounts
                lastError = nil
                refreshTask = nil
            } catch is CancellationError {
                guard currentGeneration == refreshGeneration else { return }
                refreshTask = nil
            } catch {
                guard currentGeneration == refreshGeneration else { return }
                accounts = []
                lastError = (error as? AIAccountStoreError).map(humanize) ?? error.localizedDescription
                refreshTask = nil
            }
        }
    }

    func cancelRefresh() {
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
    }

    func accounts(for provider: ProviderID) -> [ProviderAccount] {
        accounts.filter { $0.providerId == provider }
    }

    @discardableResult
    func create(_ draft: ProviderAccountDraft) -> ProviderAccount? {
        do {
            let account = try store.createAccount(draft)
            refresh()
            TokenRefreshService.shared.accountInventoryChanged()
            return account
        } catch {
            lastError = humanize(error)
            return nil
        }
    }

    func updateLabel(id: UUID, label: String) {
        do {
            _ = try store.updateAccount(
                id: id,
                label: label,
                isEnabled: nil,
                baseURLOverride: .none,
                accountEmail: .none
            )
            refresh()
            TokenRefreshService.shared.accountInventoryChanged()
        } catch {
            lastError = humanize(error)
        }
    }

    func setEnabled(id: UUID, enabled: Bool) {
        do {
            _ = try store.updateAccount(
                id: id,
                label: nil,
                isEnabled: enabled,
                baseURLOverride: .none,
                accountEmail: .none
            )
            refresh()
            TokenRefreshService.shared.accountInventoryChanged()
        } catch {
            lastError = humanize(error)
        }
    }

    func setBaseURL(id: UUID, url: URL?) {
        do {
            _ = try store.updateAccount(
                id: id,
                label: nil,
                isEnabled: nil,
                baseURLOverride: .some(url),
                accountEmail: .none
            )
            refresh()
            TokenRefreshService.shared.accountInventoryChanged()
        } catch {
            lastError = humanize(error)
        }
    }

    func delete(id: UUID) {
        do {
            try store.deleteAccount(id: id)
            FeatureRouting.clearSelections(forAccountId: id)
            refresh()
            TokenRefreshService.shared.accountInventoryChanged()
        } catch {
            lastError = humanize(error)
        }
    }

    private func humanize(_ error: Error) -> String {
        if let storeError = error as? AIAccountStoreError {
            switch storeError {
            case .vaultLocked: return "Secrets is locked. Unlock it in Settings → Secrets."
            case .accountNotFound: return "This account no longer exists."
            case .providerUnknown: return "Unknown provider."
            case .credentialMissing: return "No credentials stored for this account."
            case .duplicateLabel: return "Another account already uses this label."
            case .underlying(let msg): return msg
            }
        }
        return error.localizedDescription
    }
}
