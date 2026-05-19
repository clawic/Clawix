import XCTest
@testable import Clawix

@MainActor
final class TelegramBotsStoreCancellationTests: XCTestCase {
    func testStopRefreshingSuppressesStaleBotList() async {
        let started = expectation(description: "Telegram bot list refresh started")
        let returned = expectation(description: "Telegram bot list refresh returned")
        let store = TelegramBotsStore(
            listBotsOperation: {
                started.fulfill()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                returned.fulfill()
                return [Self.bot(id: "stale")]
            }
        )

        store.startRefreshing()
        await fulfillment(of: [started], timeout: 1)

        store.stopRefreshing()

        await fulfillment(of: [returned], timeout: 1)
        await Task.yield()
        XCTAssertTrue(store.bots.isEmpty)
        XCTAssertFalse(store.isLoading)
    }

    func testStartingSameCommandReloadCancelsStaleLoad() async {
        let slowStarted = expectation(description: "Slow command reload started")
        let slowCancelled = expectation(description: "Slow command reload cancelled")
        let fastStarted = expectation(description: "Fast command reload started")
        let bot = Self.bot(id: "main")
        var calls = 0
        let store = TelegramBotsStore(
            reloadCommandsOperation: { _ in
                calls += 1
                if calls == 1 {
                    slowStarted.fulfill()
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                    } catch is CancellationError {
                        slowCancelled.fulfill()
                        throw CancellationError()
                    }
                    return Self.commandsEnvelope(command: "stale")
                }
                fastStarted.fulfill()
                return Self.commandsEnvelope(command: "fresh")
            }
        )

        let first = Task { await store.reloadCommands(bot) }
        await fulfillment(of: [slowStarted], timeout: 1)

        let second = Task { await store.reloadCommands(bot) }

        await fulfillment(of: [slowCancelled, fastStarted], timeout: 1)
        await first.value
        await second.value

        XCTAssertEqual(store.commands[bot.id], [
            TelegramCommandSpec(command: "fresh", description: "fresh command")
        ])
    }

    func testStopRefreshingCancelsDetailReloads() async {
        let started = expectation(description: "Telegram chat reload started")
        let cancelled = expectation(description: "Telegram chat reload cancelled")
        let bot = Self.bot(id: "main")
        let store = TelegramBotsStore(
            reloadChatsOperation: { _, _ in
                started.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    cancelled.fulfill()
                    throw CancellationError()
                }
                return Self.chatsEnvelope(chatId: "stale")
            }
        )

        let task = Task { await store.reloadChats(bot) }
        await fulfillment(of: [started], timeout: 1)

        store.stopRefreshing()

        await fulfillment(of: [cancelled], timeout: 1)
        await task.value
        XCTAssertNil(store.chats[bot.id])
    }

    func testStartingSameActionCancelsStaleTelegramAction() async {
        let slowStarted = expectation(description: "Slow Telegram action started")
        let slowCancelled = expectation(description: "Slow Telegram action cancelled")
        let fastStarted = expectation(description: "Fast Telegram action started")
        let bot = Self.bot(id: "main")
        var calls = 0
        let store = TelegramBotsStore(
            listBotsOperation: { [] },
            startPollingOperation: { _ in
                calls += 1
                if calls == 1 {
                    slowStarted.fulfill()
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                    } catch is CancellationError {
                        slowCancelled.fulfill()
                        throw CancellationError()
                    }
                    return Self.envelope(stdout: "stale")
                }
                fastStarted.fulfill()
                return Self.envelope(stdout: "fresh")
            }
        )

        let first = Task { await store.startPolling(bot) }
        await fulfillment(of: [slowStarted], timeout: 1)

        let second = Task { await store.startPolling(bot) }

        await fulfillment(of: [slowCancelled, fastStarted], timeout: 1)
        await first.value
        await second.value

        XCTAssertEqual(store.lastActionResult[bot.id]?.stdout, "fresh")
        XCTAssertFalse(store.inflight.contains(bot.id))
    }

    func testCancelledSaveCommandsDoesNotReloadCommands() async {
        let slowStarted = expectation(description: "Slow command save started")
        let slowCancelled = expectation(description: "Slow command save cancelled")
        let fastStarted = expectation(description: "Fast command save started")
        let bot = Self.bot(id: "main")
        var saveCalls = 0
        var reloadCalls = 0
        let store = TelegramBotsStore(
            listBotsOperation: { [] },
            reloadCommandsOperation: { _ in
                reloadCalls += 1
                return Self.commandsEnvelope(command: "fresh")
            },
            saveCommandsOperation: { _, _ in
                saveCalls += 1
                if saveCalls == 1 {
                    slowStarted.fulfill()
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                    } catch is CancellationError {
                        slowCancelled.fulfill()
                        throw CancellationError()
                    }
                    return Self.envelope(stdout: "stale-save")
                }
                fastStarted.fulfill()
                return Self.envelope(stdout: "fresh-save")
            }
        )

        let first = Task {
            await store.saveCommands(bot, commands: [
                TelegramCommandSpec(command: "stale", description: "")
            ])
        }
        await fulfillment(of: [slowStarted], timeout: 1)

        let second = Task {
            await store.saveCommands(bot, commands: [
                TelegramCommandSpec(command: "fresh", description: "")
            ])
        }

        await fulfillment(of: [slowCancelled, fastStarted], timeout: 1)
        await first.value
        await second.value

        XCTAssertEqual(reloadCalls, 1)
        XCTAssertEqual(store.commands[bot.id], [
            TelegramCommandSpec(command: "fresh", description: "fresh command")
        ])
    }

    private static func bot(id: String) -> TelegramBot {
        TelegramBot(
            id: id,
            accountId: "acct-\(id)",
            label: "Bot \(id)",
            enabled: true,
            status: "ready",
            username: nil,
            firstName: nil,
            maskedCredential: nil,
            webhookUrl: nil,
            pollingActive: nil,
            recentErrors: nil,
            knownChats: nil,
            updatedAt: nil,
            workspace: nil
        )
    }

    private static func commandsEnvelope(command: String) -> ClawCliResult {
        ClawCliResult(
            ok: true,
            exitCode: 0,
            stdout: "",
            stderr: "",
            json: .object([
                "commands": .array([
                    .object([
                        "command": .string(command),
                        "description": .string("\(command) command")
                    ])
                ])
            ])
        )
    }

    private static func envelope(stdout: String) -> ClawCliResult {
        ClawCliResult(
            ok: true,
            exitCode: 0,
            stdout: stdout,
            stderr: "",
            json: nil
        )
    }

    private static func chatsEnvelope(chatId: String) -> ClawCliResult {
        ClawCliResult(
            ok: true,
            exitCode: 0,
            stdout: "",
            stderr: "",
            json: .object([
                "chats": .array([
                    .object([
                        "chatId": .string(chatId),
                        "title": .string("Chat \(chatId)"),
                        "type": .string("private")
                    ])
                ])
            ])
        )
    }
}
