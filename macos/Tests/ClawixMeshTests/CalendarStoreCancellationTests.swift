import SwiftUI
import XCTest
@testable import Clawix

@MainActor
final class CalendarStoreCancellationTests: XCTestCase {
    func testCancelSurfaceWorkCancelsInFlightBootstrap() async {
        let accessStarted = expectation(description: "Calendar access request started")
        let accessCancelled = expectation(description: "Calendar access request cancelled")
        let accessReturned = expectation(description: "Calendar access request should not return after cancellation")
        accessReturned.isInverted = true
        let loadUnexpected = expectation(description: "Calendar reload should not run after surface cancellation")
        loadUnexpected.isInverted = true
        let backend = Backend()
        backend.requestAccessHandler = {
            accessStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 100_000_000)
                accessReturned.fulfill()
                return .granted
            } catch is CancellationError {
                accessCancelled.fulfill()
                return .unavailable
            } catch {
                return .unavailable
            }
        }
        backend.loadSourcesHandler = {
            loadUnexpected.fulfill()
            return [Self.source(id: "unexpected")]
        }
        let store = CalendarStore(backend: backend, calendar: Self.calendar)

        let task = Task { await store.bootstrap() }
        await fulfillment(of: [accessStarted], timeout: 1)

        store.cancelSurfaceWork()

        await task.value
        await fulfillment(of: [accessCancelled, accessReturned, loadUnexpected], timeout: 1)

        XCTAssertEqual(store.access, .unknown)
        XCTAssertTrue(store.sources.isEmpty)
        XCTAssertTrue(store.events.isEmpty)
    }

    func testCancelSurfaceWorkCancelsInFlightReload() async {
        let reloadStarted = expectation(description: "Calendar reload started")
        let reloadCancelled = expectation(description: "Calendar reload cancelled")
        let backend = Backend()
        backend.loadSourcesHandler = {
            reloadStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                reloadCancelled.fulfill()
                return [Self.source(id: "cancelled")]
            } catch {
                return [Self.source(id: "failed")]
            }
            return [Self.source(id: "stale")]
        }
        let store = CalendarStore(backend: backend, calendar: Self.calendar)

        let task = Task { await store.reload() }
        await fulfillment(of: [reloadStarted], timeout: 1)

        store.cancelSurfaceWork()

        await fulfillment(of: [reloadCancelled], timeout: 1)
        await task.value

        XCTAssertTrue(store.sources.isEmpty)
        XCTAssertTrue(store.events.isEmpty)
    }

    func testStartingSecondReloadCancelsStaleReload() async {
        let staleStarted = expectation(description: "Stale reload started")
        let staleCancelled = expectation(description: "Stale reload cancelled")
        let freshStarted = expectation(description: "Fresh reload started")
        var sourceCalls = 0
        let backend = Backend()
        backend.loadSourcesHandler = {
            sourceCalls += 1
            if sourceCalls == 1 {
                staleStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    staleCancelled.fulfill()
                    return [Self.source(id: "stale")]
                } catch {
                    return [Self.source(id: "stale")]
                }
                return [Self.source(id: "stale")]
            }
            freshStarted.fulfill()
            return [Self.source(id: "fresh")]
        }
        backend.loadEventsHandler = { _, _ in [Self.event(id: "fresh")] }
        let store = CalendarStore(backend: backend, calendar: Self.calendar)

        let first = Task { await store.reload() }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { await store.reload() }

        await fulfillment(of: [staleCancelled, freshStarted], timeout: 1)
        await first.value
        await second.value

        XCTAssertEqual(store.sources.map(\.id), ["fresh"])
        XCTAssertEqual(store.events.map(\.id), ["fresh"])
    }

    func testStaleReloadCannotOverwriteFreshReload() async {
        let staleStarted = expectation(description: "Stale reload started")
        let staleReturned = expectation(description: "Stale reload returned")
        let freshStarted = expectation(description: "Fresh reload started")
        var sourceCalls = 0
        let backend = Backend()
        backend.loadSourcesHandler = {
            sourceCalls += 1
            if sourceCalls == 1 {
                staleStarted.fulfill()
                try? await Task.sleep(nanoseconds: 100_000_000)
                staleReturned.fulfill()
                return [Self.source(id: "stale")]
            }
            freshStarted.fulfill()
            return [Self.source(id: "fresh")]
        }
        backend.loadEventsHandler = { _, _ in [Self.event(id: "fresh")] }
        let store = CalendarStore(backend: backend, calendar: Self.calendar)

        let first = Task { await store.reload() }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { await store.reload() }

        await fulfillment(of: [freshStarted, staleReturned], timeout: 1)
        await first.value
        await second.value

        XCTAssertEqual(store.sources.map(\.id), ["fresh"])
        XCTAssertEqual(store.events.map(\.id), ["fresh"])
    }

    func testStartingSecondCommitCancelsStaleCommit() async {
        let staleStarted = expectation(description: "Stale save started")
        let staleCancelled = expectation(description: "Stale save cancelled")
        let freshStarted = expectation(description: "Fresh save started")
        var saveCalls = 0
        let backend = Backend()
        backend.saveHandler = { _ in
            saveCalls += 1
            if saveCalls == 1 {
                staleStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    staleCancelled.fulfill()
                    return .failure("stale save cancelled")
                } catch {
                    return .failure("stale save failed")
                }
                return .failure("stale save should not publish")
            }
            freshStarted.fulfill()
            return .success
        }
        backend.loadSourcesHandler = { [Self.source(id: "work")] }
        backend.loadEventsHandler = { _, _ in [Self.event(id: "fresh")] }
        let store = CalendarStore(backend: backend, calendar: Self.calendar)

        store.editingDraft = Self.draft(id: "event", title: "Stale")
        let first = Task { await store.commitDraft() }
        await fulfillment(of: [staleStarted], timeout: 1)

        store.editingDraft = Self.draft(id: "event", title: "Fresh")
        let second = Task { await store.commitDraft() }

        await fulfillment(of: [staleCancelled, freshStarted], timeout: 1)
        await first.value
        await second.value

        XCTAssertNil(store.editingDraft)
        XCTAssertNil(store.lastError)
        XCTAssertEqual(store.events.map(\.id), ["fresh"])
    }

    func testStartingSecondDeleteCancelsStaleDelete() async {
        let staleStarted = expectation(description: "Stale delete started")
        let staleCancelled = expectation(description: "Stale delete cancelled")
        let freshStarted = expectation(description: "Fresh delete started")
        var deleteCalls = 0
        let backend = Backend()
        backend.deleteHandler = { _ in
            deleteCalls += 1
            if deleteCalls == 1 {
                staleStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    staleCancelled.fulfill()
                    return .failure("stale delete cancelled")
                } catch {
                    return .failure("stale delete failed")
                }
                return .failure("stale delete should not publish")
            }
            freshStarted.fulfill()
            return .success
        }
        backend.loadSourcesHandler = { [Self.source(id: "work")] }
        backend.loadEventsHandler = { _, _ in [Self.event(id: "remaining")] }
        let store = CalendarStore(backend: backend, calendar: Self.calendar)
        store.selectedEventID = "event"

        let first = Task { await store.deleteEvent(Self.event(id: "event")) }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { await store.deleteEvent(Self.event(id: "event")) }

        await fulfillment(of: [staleCancelled, freshStarted], timeout: 1)
        await first.value
        await second.value

        XCTAssertNil(store.selectedEventID)
        XCTAssertNil(store.lastError)
        XCTAssertEqual(store.events.map(\.id), ["remaining"])
    }

    func testCancelSurfaceWorkCancelsInFlightCommit() async {
        let saveStarted = expectation(description: "Calendar save started")
        let saveCancelled = expectation(description: "Calendar save cancelled")
        let reloadUnexpected = expectation(description: "Calendar reload should not run after write cancellation")
        reloadUnexpected.isInverted = true
        let backend = Backend()
        backend.saveHandler = { _ in
            saveStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                saveCancelled.fulfill()
                return .failure("cancelled")
            } catch {
                return .failure("failed")
            }
            return .success
        }
        backend.loadSourcesHandler = {
            reloadUnexpected.fulfill()
            return [Self.source(id: "unexpected")]
        }
        let store = CalendarStore(backend: backend, calendar: Self.calendar)
        store.editingDraft = Self.draft(id: "event", title: "Stale")

        let task = Task { await store.commitDraft() }
        await fulfillment(of: [saveStarted], timeout: 1)

        store.cancelSurfaceWork()

        await fulfillment(of: [saveCancelled], timeout: 1)
        await task.value
        await fulfillment(of: [reloadUnexpected], timeout: 0.05)

        XCTAssertEqual(store.editingDraft?.title, "Stale")
        XCTAssertNil(store.lastError)
        XCTAssertTrue(store.events.isEmpty)
    }

    private static let calendar = Foundation.Calendar(identifier: .gregorian)

    private static func date(_ day: Int, hour: Int = 9) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.year = 2026
        components.month = 5
        components.day = day
        components.hour = hour
        return components.date!
    }

    private static func source(id: String) -> CalendarSource {
        CalendarSource(
            id: id,
            sourceID: "source-\(id)",
            title: id.capitalized,
            color: .blue,
            isSubscribed: false,
            isReadOnly: false
        )
    }

    private static func event(id: String) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: id.capitalized,
            location: nil,
            notes: nil,
            startDate: date(19),
            endDate: date(19, hour: 10),
            isAllDay: false,
            sourceID: "source-work",
            calendarID: "work"
        )
    }

    private static func draft(id: String?, title: String) -> CalendarEventDraft {
        CalendarEventDraft(
            id: id,
            title: title,
            location: nil,
            notes: nil,
            startDate: date(19),
            endDate: date(19, hour: 10),
            isAllDay: false,
            calendarID: "work"
        )
    }

    private final class Backend: CalendarBackend, @unchecked Sendable {
        var requestAccessHandler: () async -> CalendarAccessResult = { .granted }
        var loadSourcesHandler: () async -> [CalendarSource] = { [] }
        var loadEventsHandler: (Date, Date) async -> [CalendarEvent] = { _, _ in [] }
        var saveHandler: (CalendarEventDraft) async -> CalendarWriteResult = { _ in .success }
        var deleteHandler: (String) async -> CalendarWriteResult = { _ in .success }

        func requestAccess() async -> CalendarAccessResult {
            await requestAccessHandler()
        }

        func loadSources() async -> [CalendarSource] {
            await loadSourcesHandler()
        }

        func loadEvents(start: Date, end: Date) async -> [CalendarEvent] {
            await loadEventsHandler(start, end)
        }

        func save(draft: CalendarEventDraft) async -> CalendarWriteResult {
            await saveHandler(draft)
        }

        func delete(eventID: String) async -> CalendarWriteResult {
            await deleteHandler(eventID)
        }
    }
}
