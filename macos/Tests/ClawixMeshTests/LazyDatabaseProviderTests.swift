import XCTest
import GRDB
@testable import Clawix

final class LazyDatabaseProviderTests: XCTestCase {
    func testConstructionDoesNotOpenOrMigrate() {
        var openCount = 0
        var migrateCount = 0
        let provider = LazyDatabaseProvider(
            opener: {
                openCount += 1
                return try DatabaseQueue()
            },
            migrator: { _ in migrateCount += 1 }
        )

        if case .idle = provider.state {
        } else {
            XCTFail("Provider should start idle.")
        }
        XCTAssertEqual(openCount, 0)
        XCTAssertEqual(migrateCount, 0)
    }

    func testOpenIfNeededOpensAndMigratesOnce() throws {
        var openCount = 0
        var migrateCount = 0
        let provider = LazyDatabaseProvider(
            opener: {
                openCount += 1
                return try DatabaseQueue()
            },
            migrator: { _ in migrateCount += 1 }
        )

        guard case .ready = provider.openIfNeeded() else {
            return XCTFail("Expected ready provider.")
        }
        guard case .ready = provider.openIfNeeded() else {
            return XCTFail("Expected cached ready provider.")
        }

        XCTAssertNotNil(provider.dbQueue)
        XCTAssertEqual(openCount, 1)
        XCTAssertEqual(migrateCount, 1)
    }

    func testOpenFailureMapsToStorageUnavailable() {
        let provider = LazyDatabaseProvider(
            opener: { throw StubError.openFailed },
            migrator: { _ in XCTFail("Migration should not run after open failure.") }
        )

        guard case .failed(let failure) = provider.openIfNeeded() else {
            return XCTFail("Expected failed provider.")
        }
        XCTAssertEqual(failure.signal, .storageUnavailable)
    }

    func testMigrationFailureMapsToMigrationFailure() {
        let provider = LazyDatabaseProvider(
            opener: { try DatabaseQueue() },
            migrator: { _ in throw StubError.migrationFailed }
        )

        guard case .failed(let failure) = provider.openIfNeeded() else {
            return XCTFail("Expected failed provider.")
        }
        XCTAssertEqual(failure.signal, .migrationFailure)
    }

    private enum StubError: Error {
        case openFailed
        case migrationFailed
    }
}
