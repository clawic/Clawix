import AIProviders
import XCTest
@testable import Clawix

@MainActor
final class AIAccountStoreObservableCancellationTests: XCTestCase {
    func testNewRefreshCancelsStaleAccountListRefresh() async {
        let slowStarted = expectation(description: "Slow account refresh started")
        let slowCancelled = expectation(description: "Slow account refresh cancelled")
        let fastFinished = expectation(description: "Fast account refresh finished")
        var calls = 0
        let store = FakeAIAccountStore()
        let observable = AIAccountStoreObservable(
            store: store,
            refreshImmediately: false
        ) {
            calls += 1
            if calls == 1 {
                slowStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    slowCancelled.fulfill()
                    throw CancellationError()
                }
                return [Self.account(label: "stale")]
            }
            fastFinished.fulfill()
            return [Self.account(label: "current")]
        }

        observable.refresh()
        await fulfillment(of: [slowStarted], timeout: 1)

        observable.refresh()

        await fulfillment(of: [slowCancelled, fastFinished], timeout: 1)
        XCTAssertEqual(observable.accounts.map(\.label), ["current"])
        XCTAssertNil(observable.lastError)
    }

    func testCancelRefreshLeavesPreviousAccountListIntact() async {
        let started = expectation(description: "Account refresh started")
        let cancelled = expectation(description: "Account refresh cancelled")
        let store = FakeAIAccountStore()
        let observable = AIAccountStoreObservable(
            store: store,
            refreshImmediately: false
        ) {
            started.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                cancelled.fulfill()
                throw CancellationError()
            }
            return [Self.account(label: "late")]
        }

        observable.refresh()
        await fulfillment(of: [started], timeout: 1)

        observable.cancelRefresh()

        await fulfillment(of: [cancelled], timeout: 1)
        XCTAssertTrue(observable.accounts.isEmpty)
        XCTAssertNil(observable.lastError)
    }

    private static func account(label: String) -> ProviderAccount {
        ProviderAccount(
            id: UUID(),
            providerId: .openai,
            label: label,
            authMethod: .apiKey,
            isEnabled: true,
            createdAt: Date(),
            lastUsedAt: nil,
            baseURLOverride: nil,
            accountEmail: nil
        )
    }
}

private final class FakeAIAccountStore: AIAccountStore, @unchecked Sendable {
    func listAccounts() throws -> [ProviderAccount] { [] }

    func listAccounts(for provider: ProviderID) throws -> [ProviderAccount] {
        _ = provider
        return []
    }

    func createAccount(_ draft: ProviderAccountDraft) throws -> ProviderAccount {
        ProviderAccount(
            id: UUID(),
            providerId: draft.providerId,
            label: draft.label,
            authMethod: draft.authMethod,
            isEnabled: true,
            createdAt: Date(),
            lastUsedAt: nil,
            baseURLOverride: draft.baseURLOverride,
            accountEmail: draft.accountEmail
        )
    }

    func updateAccount(
        id: UUID,
        label: String?,
        isEnabled: Bool?,
        baseURLOverride: URL??,
        accountEmail: String??
    ) throws -> ProviderAccount {
        ProviderAccount(
            id: id,
            providerId: .openai,
            label: label ?? "Updated",
            authMethod: .apiKey,
            isEnabled: isEnabled ?? true,
            createdAt: Date(),
            lastUsedAt: nil,
            baseURLOverride: baseURLOverride ?? nil,
            accountEmail: accountEmail ?? nil
        )
    }

    func updateCredentials(
        accountId: UUID,
        apiKey: String?,
        accessToken: String?,
        refreshToken: String?,
        expiresAt: Date?,
        scope: String?
    ) throws {
        _ = (accountId, apiKey, accessToken, refreshToken, expiresAt, scope)
    }

    func touch(accountId: UUID) throws {
        _ = accountId
    }

    func deleteAccount(id: UUID) throws {
        _ = id
    }

    func revealCredentials(accountId: UUID) throws -> AIAccountCredentials {
        _ = accountId
        return AIAccountCredentials()
    }
}
