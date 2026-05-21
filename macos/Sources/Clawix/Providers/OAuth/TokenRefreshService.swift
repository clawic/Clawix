import AIProviders
import Combine
import Foundation

struct TokenRefreshScheduledTimer {
    let cancel: @MainActor () -> Void
}

/// Background actor that refreshes OAuth access tokens just before their
/// recorded expiry. It stays idle while the vault is locked or no OAuth
/// account has a refresh token and an expiry.
@MainActor
final class TokenRefreshService: ObservableObject {

    static let shared = TokenRefreshService()

    typealias AccountListOperation = @MainActor () throws -> [ProviderAccount]
    typealias HasRefreshTokenOperation = @MainActor (UUID) throws -> Bool
    typealias CredentialExpirationOperation = @MainActor (UUID) throws -> Date?
    typealias RefreshOperation = @MainActor (ProviderAccount, OAuthFlavor) async throws -> OAuthTokens
    typealias UpdateCredentialsOperation = @MainActor (UUID, OAuthTokens) throws -> Void
    typealias DisableAccountOperation = @MainActor (UUID) throws -> Void
    typealias ScheduleTimerOperation = @MainActor (
        _ delay: TimeInterval,
        _ tolerance: TimeInterval,
        _ fire: @escaping @MainActor () -> Void
    ) -> TokenRefreshScheduledTimer

    private struct RefreshCandidate {
        let account: ProviderAccount
        let flavor: OAuthFlavor
        let expiresAt: Date
        let attemptAt: Date
    }

    private var scheduledTimer: TokenRefreshScheduledTimer?
    private var refreshTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var isStarted = false
    private var failures: [UUID: Int] = [:]
    private var retryNotBefore: [UUID: Date] = [:]
    private let maxFailures = 3
    private let lookahead: TimeInterval
    private let retryDelay: TimeInterval
    private let dateProvider: @MainActor () -> Date
    private let isVaultUnlocked: @MainActor () -> Bool
    private let listAccounts: AccountListOperation
    private let hasRefreshToken: HasRefreshTokenOperation
    private let credentialExpiresAt: CredentialExpirationOperation
    private let refreshTokens: RefreshOperation
    private let updateCredentials: UpdateCredentialsOperation
    private let disableAccount: DisableAccountOperation
    private let refreshAccountObservable: @MainActor () -> Void
    private let scheduleTimer: ScheduleTimerOperation
    private let observeSecretsState: Bool

    init(
        lookahead: TimeInterval = 5 * 60,
        retryDelay: TimeInterval = 60,
        dateProvider: @escaping @MainActor () -> Date = { Date() },
        isVaultUnlocked: @escaping @MainActor () -> Bool = { SecretsManager.shared.state == .unlocked },
        listAccounts: @escaping AccountListOperation = { try AIAccountSecretsStore.shared.listAccounts() },
        hasRefreshToken: @escaping HasRefreshTokenOperation = {
            try AIAccountSecretsStore.shared.hasCredentialField(accountId: $0, fieldName: "refresh_token")
        },
        credentialExpiresAt: @escaping CredentialExpirationOperation = {
            try AIAccountSecretsStore.shared.credentialExpiresAt(accountId: $0)
        },
        refreshTokens: @escaping RefreshOperation = { account, flavor in
            switch flavor {
            case .anthropicClaudeAi:
                return try await AnthropicOAuthStrategy().refresh(account: account)
            }
        },
        updateCredentials: @escaping UpdateCredentialsOperation = { accountId, tokens in
            guard let refreshedRefreshToken = tokens.refreshToken else {
                throw AIClientError.provider("OAuth refresh did not return a replacement refresh token.")
            }
            try AIAccountSecretsStore.shared.updateCredentials(
                accountId: accountId,
                apiKey: nil,
                accessToken: tokens.accessToken,
                refreshToken: refreshedRefreshToken,
                expiresAt: tokens.expiresAt,
                scope: tokens.scope
            )
        },
        disableAccount: @escaping DisableAccountOperation = {
            _ = try AIAccountSecretsStore.shared.updateAccount(
                id: $0,
                label: nil,
                isEnabled: false,
                baseURLOverride: .none,
                accountEmail: .none
            )
        },
        refreshAccountObservable: @escaping @MainActor () -> Void = {
            AIAccountStoreObservable.shared.refresh()
        },
        scheduleTimer: @escaping ScheduleTimerOperation = TokenRefreshService.scheduleOneShotTimer,
        observeSecretsState: Bool = true
    ) {
        self.lookahead = lookahead
        self.retryDelay = retryDelay
        self.dateProvider = dateProvider
        self.isVaultUnlocked = isVaultUnlocked
        self.listAccounts = listAccounts
        self.hasRefreshToken = hasRefreshToken
        self.credentialExpiresAt = credentialExpiresAt
        self.refreshTokens = refreshTokens
        self.updateCredentials = updateCredentials
        self.disableAccount = disableAccount
        self.refreshAccountObservable = refreshAccountObservable
        self.scheduleTimer = scheduleTimer
        self.observeSecretsState = observeSecretsState
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        if observeSecretsState {
            SecretsManager.shared.$state
                .sink { [weak self] state in
                    Task { @MainActor in self?.secretsStateChanged(state) }
                }
                .store(in: &cancellables)
        }
        reconcileSchedule()
    }

    func stop() {
        isStarted = false
        cancellables.removeAll()
        cancelScheduledTimer()
        refreshTask?.cancel()
        refreshTask = nil
    }

    func accountInventoryChanged() {
        guard isStarted else { return }
        reconcileSchedule()
    }

    private func secretsStateChanged(_ state: SecretsManager.State) {
        guard isStarted else { return }
        switch state {
        case .unlocked:
            reconcileSchedule()
        case .loading, .uninitialized, .locked, .unlocking, .openFailed:
            cancelScheduledTimer()
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    private func reconcileSchedule() {
        cancelScheduledTimer()
        guard isStarted, isVaultUnlocked() else { return }
        let candidates = eligibleCandidates()
        guard !candidates.isEmpty else { return }
        let now = dateProvider()
        let due = candidates.filter { $0.attemptAt <= now }
        if !due.isEmpty {
            startRefresh(for: due)
            return
        }
        guard refreshTask == nil, let next = candidates.min(by: { $0.attemptAt < $1.attemptAt }) else { return }
        let delay = max(0, next.attemptAt.timeIntervalSince(now))
        let tolerance = timerTolerance(forDelay: delay)
        scheduledTimer = scheduleTimer(delay, tolerance) { [weak self] in
            self?.scheduledTimerDidFire()
        }
    }

    private func scheduledTimerDidFire() {
        scheduledTimer = nil
        reconcileSchedule()
    }

    private func cancelScheduledTimer() {
        scheduledTimer?.cancel()
        scheduledTimer = nil
    }

    private func eligibleCandidates() -> [RefreshCandidate] {
        let accounts = (try? listAccounts()) ?? []
        let now = dateProvider()
        return accounts.compactMap { account in
            guard account.isEnabled, case .oauth(let flavor) = account.authMethod else { return nil }
            do {
                guard try hasRefreshToken(account.id) else { return nil }
                guard let expiresAt = try credentialExpiresAt(account.id) else { return nil }
                let refreshAt = expiresAt.addingTimeInterval(-lookahead)
                let retryAt = retryNotBefore[account.id] ?? .distantPast
                return RefreshCandidate(
                    account: account,
                    flavor: flavor,
                    expiresAt: expiresAt,
                    attemptAt: max(refreshAt, retryAt, now.addingTimeInterval(-1))
                )
            } catch {
                return nil
            }
        }
    }

    private func startRefresh(for candidates: [RefreshCandidate]) {
        guard refreshTask == nil else { return }
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refresh(candidates)
            guard !Task.isCancelled else { return }
            self.refreshTask = nil
            self.reconcileSchedule()
        }
    }

    private func refresh(_ candidates: [RefreshCandidate]) async {
        var changedAccounts = false
        for candidate in candidates {
            guard !Task.isCancelled else { return }
            do {
                let tokens = try await refreshTokens(candidate.account, candidate.flavor)
                try Task.checkCancellation()
                try updateCredentials(candidate.account.id, tokens)
                failures[candidate.account.id] = 0
                retryNotBefore[candidate.account.id] = nil
                changedAccounts = true
            } catch is CancellationError {
                return
            } catch {
                let accountId = candidate.account.id
                let count = (failures[accountId] ?? 0) + 1
                failures[accountId] = count
                retryNotBefore[accountId] = dateProvider().addingTimeInterval(retryDelay)
                if count >= maxFailures {
                    _ = try? disableAccount(accountId)
                    changedAccounts = true
                }
            }
        }
        guard !Task.isCancelled, changedAccounts else { return }
        refreshAccountObservable()
    }

    private func timerTolerance(forDelay delay: TimeInterval) -> TimeInterval {
        guard delay > 0 else { return 0 }
        return min(60, delay / 10)
    }

    private static func scheduleOneShotTimer(
        delay: TimeInterval,
        tolerance: TimeInterval,
        fire: @escaping @MainActor () -> Void
    ) -> TokenRefreshScheduledTimer {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            Task { @MainActor in fire() }
        }
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        return TokenRefreshScheduledTimer {
            timer.invalidate()
        }
    }
}
