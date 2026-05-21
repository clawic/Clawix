import AIProviders
import XCTest
@testable import Clawix

@MainActor
final class TokenRefreshServiceTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_000_000)
    private var vaultUnlocked = true
    private var accounts: [ProviderAccount] = []
    private var refreshTokenAccountIds: Set<UUID> = []
    private var expirations: [UUID: Date] = [:]
    private var updatedAccountIds: [UUID] = []
    private var disabledAccountIds: [UUID] = []
    private var accountObservableRefreshCount = 0
    private var refreshOperation: ((ProviderAccount) async throws -> OAuthTokens)?
    private var timerRecorder = TimerRecorder()

    override func tearDown() {
        refreshOperation = nil
        super.tearDown()
    }

    func testLockedVaultDoesNotScheduleOrRefresh() async {
        vaultUnlocked = false
        let account = oauthAccount()
        accounts = [account]
        refreshTokenAccountIds = [account.id]
        expirations[account.id] = now.addingTimeInterval(30)

        let service = makeService()
        service.start()

        XCTAssertTrue(timerRecorder.scheduled.isEmpty)
        XCTAssertTrue(updatedAccountIds.isEmpty)
    }

    func testUnlockedVaultWithNoAccountsDoesNotSchedule() async {
        let service = makeService()
        service.start()

        XCTAssertTrue(timerRecorder.scheduled.isEmpty)
    }

    func testOAuthAccountWithoutExpiryDoesNotSchedule() async {
        let account = oauthAccount()
        accounts = [account]
        refreshTokenAccountIds = [account.id]

        let service = makeService()
        service.start()

        XCTAssertTrue(timerRecorder.scheduled.isEmpty)
    }

    func testSchedulesOneShotForNextOAuthExpiryMinusLookahead() async {
        let account = oauthAccount()
        accounts = [account]
        refreshTokenAccountIds = [account.id]
        expirations[account.id] = now.addingTimeInterval(900)

        let service = makeService()
        service.start()

        XCTAssertEqual(timerRecorder.scheduled.count, 1)
        XCTAssertEqual(timerRecorder.scheduled[0].delay, 600, accuracy: 0.001)
        XCTAssertEqual(timerRecorder.scheduled[0].tolerance, 60, accuracy: 0.001)
        XCTAssertTrue(updatedAccountIds.isEmpty)
    }

    func testDueOAuthAccountRefreshesImmediatelyThenReschedules() async {
        let updated = expectation(description: "Due OAuth account refreshed")
        let account = oauthAccount()
        accounts = [account]
        refreshTokenAccountIds = [account.id]
        expirations[account.id] = now.addingTimeInterval(30)
        refreshOperation = { [now] _ in
            OAuthTokens(
                accessToken: "new-access-token",
                refreshToken: "new-refresh-token",
                expiresAt: now.addingTimeInterval(1_200),
                scope: nil,
                accountEmail: nil
            )
        }

        let service = makeService(onUpdate: { updated.fulfill() })
        service.start()

        await fulfillment(of: [updated], timeout: 1)
        await waitUntil { self.timerRecorder.activeCount == 1 }

        XCTAssertEqual(updatedAccountIds, [account.id])
        XCTAssertEqual(accountObservableRefreshCount, 1)
        XCTAssertEqual(try XCTUnwrap(timerRecorder.scheduled.last?.delay), 900, accuracy: 0.001)
    }

    func testFailedDueRefreshRetriesAfterDelayAndDisablesAfterThreeFailures() async {
        let account = oauthAccount()
        accounts = [account]
        refreshTokenAccountIds = [account.id]
        expirations[account.id] = now.addingTimeInterval(30)
        var attempts = 0
        refreshOperation = { _ in
            attempts += 1
            throw AIClientError.provider("refresh failed")
        }

        let service = makeService()
        service.start()
        await waitUntil { attempts == 1 && self.timerRecorder.activeCount == 1 }

        XCTAssertEqual(try XCTUnwrap(timerRecorder.scheduled.last?.delay), 60, accuracy: 0.001)
        XCTAssertTrue(disabledAccountIds.isEmpty)

        now = now.addingTimeInterval(60)
        timerRecorder.scheduled.last?.fire()
        await waitUntil { attempts == 2 && self.timerRecorder.activeCount == 1 }

        now = now.addingTimeInterval(60)
        timerRecorder.scheduled.last?.fire()
        await waitUntil { attempts == 3 && self.timerRecorder.activeCount == 0 }

        XCTAssertEqual(disabledAccountIds, [account.id])
        XCTAssertEqual(accountObservableRefreshCount, 1)
        XCTAssertEqual(accounts.first?.isEnabled, false)
    }

    func testStopCancelsPendingOneShotTimer() async {
        let account = oauthAccount()
        accounts = [account]
        refreshTokenAccountIds = [account.id]
        expirations[account.id] = now.addingTimeInterval(900)

        let service = makeService()
        service.start()
        XCTAssertEqual(timerRecorder.activeCount, 1)

        service.stop()

        XCTAssertEqual(timerRecorder.activeCount, 0)
        XCTAssertEqual(timerRecorder.cancelCount, 1)
    }

    func testStopCancelsRunningTokenRefresh() async {
        let started = expectation(description: "Token refresh started")
        let cancelled = expectation(description: "Token refresh cancelled")
        let account = oauthAccount()
        accounts = [account]
        refreshTokenAccountIds = [account.id]
        expirations[account.id] = now.addingTimeInterval(30)
        refreshOperation = { _ in
            started.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                cancelled.fulfill()
                throw CancellationError()
            }
            return OAuthTokens(
                accessToken: "new-access-token",
                refreshToken: "new-refresh-token",
                expiresAt: self.now.addingTimeInterval(1_200),
                scope: nil,
                accountEmail: nil
            )
        }

        let service = makeService()
        service.start()
        await fulfillment(of: [started], timeout: 1)

        service.stop()

        await fulfillment(of: [cancelled], timeout: 1)
    }

    private func makeService(onUpdate: (() -> Void)? = nil) -> TokenRefreshService {
        TokenRefreshService(
            lookahead: 300,
            retryDelay: 60,
            dateProvider: { self.now },
            isVaultUnlocked: { self.vaultUnlocked },
            listAccounts: { self.accounts },
            hasRefreshToken: { self.refreshTokenAccountIds.contains($0) },
            credentialExpiresAt: { self.expirations[$0] },
            refreshTokens: { account, _ in
                if let refreshOperation = self.refreshOperation {
                    return try await refreshOperation(account)
                }
                return OAuthTokens(
                    accessToken: "new-access-token",
                    refreshToken: "new-refresh-token",
                    expiresAt: self.now.addingTimeInterval(1_200),
                    scope: nil,
                    accountEmail: nil
                )
            },
            updateCredentials: { accountId, tokens in
                self.updatedAccountIds.append(accountId)
                if let expiresAt = tokens.expiresAt {
                    self.expirations[accountId] = expiresAt
                }
                onUpdate?()
            },
            disableAccount: { accountId in
                self.disabledAccountIds.append(accountId)
                if let index = self.accounts.firstIndex(where: { $0.id == accountId }) {
                    self.accounts[index].isEnabled = false
                }
            },
            refreshAccountObservable: {
                self.accountObservableRefreshCount += 1
            },
            scheduleTimer: { delay, tolerance, fire in
                self.timerRecorder.schedule(delay: delay, tolerance: tolerance, fire: fire)
            },
            observeSecretsState: false
        )
    }

    private func oauthAccount(id: UUID = UUID(), enabled: Bool = true) -> ProviderAccount {
        ProviderAccount(
            id: id,
            providerId: .anthropic,
            label: "Personal",
            authMethod: .oauth(.anthropicClaudeAi),
            isEnabled: enabled,
            createdAt: now
        )
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let start = DispatchTime.now().uptimeNanoseconds
        while !condition(), DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

@MainActor
private final class TimerRecorder {
    struct Scheduled {
        let delay: TimeInterval
        let tolerance: TimeInterval
        let fire: @MainActor () -> Void
    }

    private var nextId = 0
    private var activeIds: Set<Int> = []
    private(set) var scheduled: [Scheduled] = []
    private(set) var cancelCount = 0

    var activeCount: Int {
        activeIds.count
    }

    func schedule(
        delay: TimeInterval,
        tolerance: TimeInterval,
        fire: @escaping @MainActor () -> Void
    ) -> TokenRefreshScheduledTimer {
        let id = nextId
        nextId += 1
        activeIds.insert(id)
        scheduled.append(Scheduled(
            delay: delay,
            tolerance: tolerance,
            fire: { [weak self] in
                self?.activeIds.remove(id)
                fire()
            }
        ))
        return TokenRefreshScheduledTimer { [weak self] in
            self?.activeIds.remove(id)
            self?.cancelCount += 1
        }
    }
}
