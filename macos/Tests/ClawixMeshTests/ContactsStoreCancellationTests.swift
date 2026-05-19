import SwiftUI
import XCTest
@testable import Clawix

@MainActor
final class ContactsStoreCancellationTests: XCTestCase {
    func testCancelSurfaceWorkCancelsInFlightBootstrap() async {
        let accessStarted = expectation(description: "Contacts access request started")
        let accessCancelled = expectation(description: "Contacts access request cancelled")
        let accessReturned = expectation(description: "Contacts access request should not return after cancellation")
        accessReturned.isInverted = true
        let loadUnexpected = expectation(description: "Contacts reload should not run after surface cancellation")
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
        backend.loadContactsHandler = {
            loadUnexpected.fulfill()
            return [Self.contact(id: "unexpected")]
        }
        let store = ContactsStore(backend: backend)

        let task = Task { await store.bootstrap() }
        await fulfillment(of: [accessStarted], timeout: 1)

        store.cancelSurfaceWork()

        await task.value
        await fulfillment(of: [accessCancelled, accessReturned, loadUnexpected], timeout: 1)

        XCTAssertEqual(store.access, .unknown)
        XCTAssertTrue(store.contacts.isEmpty)
        XCTAssertNil(store.selectedContactID)
    }

    func testCancelSurfaceWorkCancelsInFlightReload() async {
        let reloadStarted = expectation(description: "Contacts reload started")
        let reloadCancelled = expectation(description: "Contacts reload cancelled")
        let backend = Backend()
        backend.loadContactsHandler = {
            reloadStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                reloadCancelled.fulfill()
                return [Self.contact(id: "cancelled")]
            } catch {
                return [Self.contact(id: "failed")]
            }
            return [Self.contact(id: "stale")]
        }
        let store = ContactsStore(backend: backend)

        let task = Task { await store.reload() }
        await fulfillment(of: [reloadStarted], timeout: 1)

        store.cancelSurfaceWork()

        await fulfillment(of: [reloadCancelled], timeout: 1)
        await task.value

        XCTAssertTrue(store.contacts.isEmpty)
        XCTAssertNil(store.selectedContactID)
    }

    func testStartingSecondReloadCancelsStaleReload() async {
        let staleStarted = expectation(description: "Stale contacts reload started")
        let staleCancelled = expectation(description: "Stale contacts reload cancelled")
        let freshStarted = expectation(description: "Fresh contacts reload started")
        var calls = 0
        let backend = Backend()
        backend.loadContactsHandler = {
            calls += 1
            if calls == 1 {
                staleStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    staleCancelled.fulfill()
                    return [Self.contact(id: "stale")]
                } catch {
                    return [Self.contact(id: "stale")]
                }
                return [Self.contact(id: "stale")]
            }
            freshStarted.fulfill()
            return [Self.contact(id: "fresh")]
        }
        let store = ContactsStore(backend: backend)

        let first = Task { await store.reload() }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { await store.reload() }

        await fulfillment(of: [staleCancelled, freshStarted], timeout: 1)
        await first.value
        await second.value

        XCTAssertEqual(store.contacts.map(\.id), ["fresh"])
        XCTAssertEqual(store.selectedContactID, "fresh")
    }

    func testStaleReloadCannotOverwriteFreshReload() async {
        let staleStarted = expectation(description: "Stale contacts reload started")
        let staleReturned = expectation(description: "Stale contacts reload returned")
        let freshStarted = expectation(description: "Fresh contacts reload started")
        var calls = 0
        let backend = Backend()
        backend.loadContactsHandler = {
            calls += 1
            if calls == 1 {
                staleStarted.fulfill()
                try? await Task.sleep(nanoseconds: 100_000_000)
                staleReturned.fulfill()
                return [Self.contact(id: "stale")]
            }
            freshStarted.fulfill()
            return [Self.contact(id: "fresh")]
        }
        let store = ContactsStore(backend: backend)

        let first = Task { await store.reload() }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { await store.reload() }

        await fulfillment(of: [freshStarted, staleReturned], timeout: 1)
        await first.value
        await second.value

        XCTAssertEqual(store.contacts.map(\.id), ["fresh"])
    }

    func testStartingSecondCommitCancelsStaleCommit() async {
        let staleStarted = expectation(description: "Stale contact save started")
        let staleCancelled = expectation(description: "Stale contact save cancelled")
        let freshStarted = expectation(description: "Fresh contact save started")
        var saveCalls = 0
        let backend = Backend()
        backend.saveHandler = { contact in
            saveCalls += 1
            if saveCalls == 1 {
                staleStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    staleCancelled.fulfill()
                    return .failure(TestError.cancelled)
                } catch {
                    return .failure(TestError.cancelled)
                }
                return .failure(TestError.stale)
            }
            freshStarted.fulfill()
            return .success(contact)
        }
        backend.loadContactsHandler = { [Self.contact(id: "fresh")] }
        let store = ContactsStore(backend: backend)
        store.isEditing = true

        let first = Task { await store.commit(Self.contact(id: "stale")) }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { await store.commit(Self.contact(id: "fresh")) }

        await fulfillment(of: [staleCancelled, freshStarted], timeout: 1)
        await first.value
        await second.value

        XCTAssertEqual(store.contacts.map(\.id), ["fresh"])
        XCTAssertEqual(store.selectedContactID, "fresh")
        XCTAssertFalse(store.isEditing)
    }

    func testStartingSecondDeleteCancelsStaleDelete() async {
        let staleStarted = expectation(description: "Stale contact delete started")
        let staleCancelled = expectation(description: "Stale contact delete cancelled")
        let freshStarted = expectation(description: "Fresh contact delete started")
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
                    return .failure(TestError.cancelled)
                } catch {
                    return .failure(TestError.cancelled)
                }
                return .failure(TestError.stale)
            }
            freshStarted.fulfill()
            return .success(())
        }
        backend.loadContactsHandler = { [Self.contact(id: "remaining")] }
        let store = ContactsStore(backend: backend)
        store.selectedContactID = "target"

        let first = Task { await store.delete("target") }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { await store.delete("target") }

        await fulfillment(of: [staleCancelled, freshStarted], timeout: 1)
        await first.value
        await second.value

        XCTAssertEqual(store.selectedContactID, "remaining")
        XCTAssertEqual(store.contacts.map(\.id), ["remaining"])
    }

    func testCancelSurfaceWorkCancelsInFlightCommit() async {
        let saveStarted = expectation(description: "Contact save started")
        let saveCancelled = expectation(description: "Contact save cancelled")
        let reloadUnexpected = expectation(description: "Contacts reload should not run after write cancellation")
        reloadUnexpected.isInverted = true
        let backend = Backend()
        backend.saveHandler = { contact in
            saveStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                saveCancelled.fulfill()
                return .failure(TestError.cancelled)
            } catch {
                return .failure(TestError.cancelled)
            }
            return .success(contact)
        }
        backend.loadContactsHandler = {
            reloadUnexpected.fulfill()
            return [Self.contact(id: "unexpected")]
        }
        let store = ContactsStore(backend: backend)
        store.isEditing = true
        store.selectedContactID = "existing"

        let task = Task { await store.commit(Self.contact(id: "stale")) }
        await fulfillment(of: [saveStarted], timeout: 1)

        store.cancelSurfaceWork()

        await fulfillment(of: [saveCancelled], timeout: 1)
        await task.value
        await fulfillment(of: [reloadUnexpected], timeout: 0.05)

        XCTAssertTrue(store.contacts.isEmpty)
        XCTAssertEqual(store.selectedContactID, "existing")
        XCTAssertTrue(store.isEditing)
    }

    private static func contact(id: String) -> Contact {
        Contact(
            id: id,
            givenName: id.capitalized,
            familyName: "Contact",
            organization: nil,
            jobTitle: nil,
            photoData: nil,
            fields: [],
            groupIDs: [],
            accountID: "local",
            isFavorite: false,
            dateAdded: Date(timeIntervalSince1970: 0),
            note: nil
        )
    }

    private enum TestError: Error {
        case cancelled
        case stale
    }

    private final class Backend: ContactsBackend, @unchecked Sendable {
        let isReadOnly = false
        var requestAccessHandler: () async -> ContactsAccessResult = { .granted }
        var loadAccountsHandler: () async -> [ContactsAccount] = { [.init(id: "local", title: "Local")] }
        var loadGroupsHandler: () async -> [ContactsGroup] = { [] }
        var loadContactsHandler: () async -> [Contact] = { [] }
        var saveHandler: (Contact) async -> Result<Contact, Error> = { .success($0) }
        var deleteHandler: (String) async -> Result<Void, Error> = { _ in .success(()) }
        var mergeHandler: ([String]) async -> Result<Contact, Error> = { ids in
            .success(
                Contact(
                    id: ids.first ?? "merged",
                    givenName: "Merged",
                    familyName: "Contact",
                    organization: nil,
                    jobTitle: nil,
                    photoData: nil,
                    fields: [],
                    groupIDs: [],
                    accountID: "local",
                    isFavorite: false,
                    dateAdded: Date(timeIntervalSince1970: 0),
                    note: nil
                )
            )
        }
        var saveGroupHandler: (ContactsGroup) async -> Result<ContactsGroup, Error> = { .success($0) }
        var deleteGroupHandler: (String) async -> Result<Void, Error> = { _ in .success(()) }
        var toggleMembershipHandler: (String, String, Bool) async -> Result<Void, Error> = { _, _, _ in .success(()) }

        func requestAccess() async -> ContactsAccessResult {
            await requestAccessHandler()
        }

        func loadAccounts() async -> [ContactsAccount] {
            await loadAccountsHandler()
        }

        func loadGroups() async -> [ContactsGroup] {
            await loadGroupsHandler()
        }

        func loadContacts() async -> [Contact] {
            await loadContactsHandler()
        }

        func save(_ contact: Contact) async -> Result<Contact, Error> {
            await saveHandler(contact)
        }

        func delete(_ contactID: String) async -> Result<Void, Error> {
            await deleteHandler(contactID)
        }

        func merge(_ contactIDs: [String]) async -> Result<Contact, Error> {
            await mergeHandler(contactIDs)
        }

        func saveGroup(_ group: ContactsGroup) async -> Result<ContactsGroup, Error> {
            await saveGroupHandler(group)
        }

        func deleteGroup(_ groupID: String) async -> Result<Void, Error> {
            await deleteGroupHandler(groupID)
        }

        func toggleMembership(contactID: String, groupID: String, included: Bool) async -> Result<Void, Error> {
            await toggleMembershipHandler(contactID, groupID, included)
        }
    }
}
