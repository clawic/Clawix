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
                lastError = humanize(error, surface: "settings.providers.refresh")
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
            lastError = humanize(error, surface: "settings.providers.createAccount")
            return nil
        }
    }

    @discardableResult
    func updateLabel(id: UUID, label: String) -> Bool {
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
            return true
        } catch {
            lastError = humanize(error, surface: "settings.providers.updateLabel")
            return false
        }
    }

    @discardableResult
    func setEnabled(id: UUID, enabled: Bool) -> Bool {
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
            return true
        } catch {
            lastError = humanize(error, surface: "settings.providers.setEnabled")
            return false
        }
    }

    @discardableResult
    func setBaseURL(id: UUID, url: URL?) -> Bool {
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
            return true
        } catch {
            lastError = humanize(error, surface: "settings.providers.setBaseURL")
            return false
        }
    }

    @discardableResult
    func delete(id: UUID) -> Bool {
        do {
            try store.deleteAccount(id: id)
            FeatureRouting.clearSelections(forAccountId: id)
            refresh()
            TokenRefreshService.shared.accountInventoryChanged()
            return true
        } catch {
            lastError = humanize(error, surface: "settings.providers.deleteAccount")
            return false
        }
    }

    private func humanize(_ error: Error, surface: String) -> String {
        if let storeError = error as? AIAccountStoreError {
            switch storeError {
            case .vaultLocked:
                return logSpecificFailure(L10n.t("Secrets is locked. Unlock it in Settings > Secrets."), surface: surface)
            case .accountNotFound:
                return logSpecificFailure(L10n.t("This account no longer exists."), surface: surface)
            case .providerUnknown:
                return logSpecificFailure(L10n.t("Unknown provider."), surface: surface)
            case .credentialMissing:
                return logSpecificFailure(L10n.t("No credentials stored for this account."), surface: surface)
            case .duplicateLabel:
                return logSpecificFailure(L10n.t("Another account already uses this label."), surface: surface)
            case .underlying(let msg):
                return classifiedFailure(msg, surface: surface)
            }
        }
        return classifiedFailure(
            (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
            surface: surface
        )
    }

    private func logSpecificFailure(_ message: String, surface: String) -> String {
        let failure = UserFacingFailure.classify(message)
        failure.log(surface: surface)
        return message
    }

    private func classifiedFailure(_ message: String, surface: String) -> String {
        let failure = UserFacingFailure.classify(message)
        failure.log(surface: surface)
        return failure.displayMessage
    }
}
