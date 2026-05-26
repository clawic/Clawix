import XCTest
@testable import Clawix

final class ChatSidebarStateTests: XCTestCase {
    override func tearDown() {
        FaviconCache.shared.setPrefetchObserverForTesting(nil)
        super.tearDown()
    }

    func testSimulatorSidebarItemsRoundTripThroughCodableState() throws {
        let iosId = UUID()
        let androidId = UUID()
        let iosUDID = "4B28C82C-D4EB-42E4-BA0F-D9A1DE603E97"
        var state = ChatSidebarState(
            isOpen: true,
            items: [
                .iosSimulator(.init(id: iosId, deviceUDID: iosUDID, deviceName: "iPhone 17")),
                .androidSimulator(.init(id: androidId, avdName: "clawix_pixel_tablet", deviceName: "Pixel Tablet"))
            ],
            activeItemId: androidId
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ChatSidebarState.self, from: data)

        XCTAssertEqual(decoded, state)
        XCTAssertEqual(decoded.activeItem?.id, androidId)

        state.activeItemId = iosId
        XCTAssertEqual(state.activeItem?.id, iosId)
    }

    @MainActor
    func testLoadingPersistedSidebarsDoesNotPrefetchFavicons() throws {
        let defaults = AppState.sidebarDefaults
        let originalChatSidebars = defaults.object(forKey: AppState.chatSidebarsKey)
        let originalGlobalSidebar = defaults.object(forKey: AppState.globalSidebarKey)
        let originalHostFavicons = defaults.object(forKey: AppState.hostFaviconsKey)
        defer {
            restore(originalChatSidebars, key: AppState.chatSidebarsKey, defaults: defaults)
            restore(originalGlobalSidebar, key: AppState.globalSidebarKey, defaults: defaults)
            restore(originalHostFavicons, key: AppState.hostFaviconsKey, defaults: defaults)
        }

        let chatId = UUID()
        let chatFavicon = try XCTUnwrap(URL(string: "https://example.com/favicon.ico"))
        let globalFavicon = try XCTUnwrap(URL(string: "https://global.example/favicon.ico"))
        let chatWebId = UUID()
        let globalWebId = UUID()
        let chatSidebar = ChatSidebarState(
            isOpen: true,
            items: [
                .web(.init(
                    id: chatWebId,
                    url: try XCTUnwrap(URL(string: "https://example.com")),
                    title: "Example",
                    faviconURL: chatFavicon
                ))
            ],
            activeItemId: chatWebId
        )
        let globalSidebar = ChatSidebarState(
            isOpen: true,
            items: [
                .web(.init(
                    id: globalWebId,
                    url: try XCTUnwrap(URL(string: "https://global.example")),
                    title: "Global",
                    faviconURL: globalFavicon
                ))
            ],
            activeItemId: globalWebId
        )

        defaults.set(
            try JSONEncoder().encode([chatId.uuidString: chatSidebar]),
            forKey: AppState.chatSidebarsKey
        )
        defaults.set(
            try JSONEncoder().encode(globalSidebar),
            forKey: AppState.globalSidebarKey
        )
        defaults.removeObject(forKey: AppState.hostFaviconsKey)

        var prefetches: [URL] = []
        FaviconCache.shared.setPrefetchObserverForTesting { url, _ in
            prefetches.append(url)
        }

        let state = AppState()

        XCTAssertEqual(state.chatSidebars[chatId]?.items, chatSidebar.items)
        XCTAssertEqual(state.chatSidebars[chatId]?.activeItemId, chatSidebar.activeItemId)
        XCTAssertEqual(state.globalSidebar.items, globalSidebar.items)
        XCTAssertEqual(state.globalSidebar.activeItemId, globalSidebar.activeItemId)
        XCTAssertFalse(state.chatSidebars[chatId]?.isOpen ?? true)
        XCTAssertFalse(state.globalSidebar.isOpen)
        XCTAssertTrue(prefetches.isEmpty)
    }

    @MainActor
    func testLoadingPersistedSidebarsPreservesTabsButStartsClosed() throws {
        let defaults = AppState.sidebarDefaults
        let originalChatSidebars = defaults.object(forKey: AppState.chatSidebarsKey)
        let originalGlobalSidebar = defaults.object(forKey: AppState.globalSidebarKey)
        defer {
            restore(originalChatSidebars, key: AppState.chatSidebarsKey, defaults: defaults)
            restore(originalGlobalSidebar, key: AppState.globalSidebarKey, defaults: defaults)
        }

        let chatId = UUID()
        let fileId = UUID()
        let globalFileId = UUID()
        let chatSidebar = ChatSidebarState(
            isOpen: true,
            items: [.file(.init(id: fileId, path: "/tmp/heavy.md"))],
            activeItemId: fileId
        )
        let globalSidebar = ChatSidebarState(
            isOpen: true,
            items: [.file(.init(id: globalFileId, path: "/tmp/global-heavy.md"))],
            activeItemId: globalFileId
        )

        defaults.set(
            try JSONEncoder().encode([chatId.uuidString: chatSidebar]),
            forKey: AppState.chatSidebarsKey
        )
        defaults.set(
            try JSONEncoder().encode(globalSidebar),
            forKey: AppState.globalSidebarKey
        )

        let state = AppState()

        XCTAssertEqual(state.chatSidebars[chatId]?.items, chatSidebar.items)
        XCTAssertEqual(state.chatSidebars[chatId]?.activeItemId, fileId)
        XCTAssertFalse(state.chatSidebars[chatId]?.isOpen ?? true)
        XCTAssertEqual(state.globalSidebar.items, globalSidebar.items)
        XCTAssertEqual(state.globalSidebar.activeItemId, globalFileId)
        XCTAssertFalse(state.globalSidebar.isOpen)
    }

    @MainActor
    func testLoadingHostFaviconsDoesNotPrefetchSavedHosts() throws {
        let defaults = AppState.sidebarDefaults
        let originalChatSidebars = defaults.object(forKey: AppState.chatSidebarsKey)
        let originalGlobalSidebar = defaults.object(forKey: AppState.globalSidebarKey)
        let originalHostFavicons = defaults.object(forKey: AppState.hostFaviconsKey)
        defer {
            restore(originalChatSidebars, key: AppState.chatSidebarsKey, defaults: defaults)
            restore(originalGlobalSidebar, key: AppState.globalSidebarKey, defaults: defaults)
            restore(originalHostFavicons, key: AppState.hostFaviconsKey, defaults: defaults)
        }

        let favicon = try XCTUnwrap(URL(string: "https://host.example/favicon.ico"))
        defaults.removeObject(forKey: AppState.chatSidebarsKey)
        defaults.removeObject(forKey: AppState.globalSidebarKey)
        defaults.set(
            try JSONEncoder().encode(["host.example": favicon]),
            forKey: AppState.hostFaviconsKey
        )

        var prefetches: [URL] = []
        FaviconCache.shared.setPrefetchObserverForTesting { url, _ in
            prefetches.append(url)
        }

        let state = AppState()

        XCTAssertEqual(state.hostFavicons["host.example"], favicon)
        XCTAssertTrue(prefetches.isEmpty)
    }

    func testVisibleSidebarFaviconURLsAreBoundedDedupedAndWebOnly() throws {
        let first = try XCTUnwrap(URL(string: "https://first.example/favicon.ico"))
        let second = try XCTUnwrap(URL(string: "https://second.example/favicon.ico"))
        let third = try XCTUnwrap(URL(string: "https://third.example/favicon.ico"))
        let items: [SidebarItem] = [
            .file(.init(id: UUID(), path: "/tmp/file.txt")),
            .web(.init(
                id: UUID(),
                url: try XCTUnwrap(URL(string: "https://first.example")),
                title: "First",
                faviconURL: first
            )),
            .web(.init(
                id: UUID(),
                url: try XCTUnwrap(URL(string: "https://duplicate.example")),
                title: "Duplicate",
                faviconURL: first
            )),
            .chat(.init(id: UUID())),
            .web(.init(
                id: UUID(),
                url: try XCTUnwrap(URL(string: "https://second.example")),
                title: "Second",
                faviconURL: second
            )),
            .web(.init(
                id: UUID(),
                url: try XCTUnwrap(URL(string: "https://missing.example")),
                title: "Missing favicon"
            )),
            .web(.init(
                id: UUID(),
                url: try XCTUnwrap(URL(string: "https://third.example")),
                title: "Third",
                faviconURL: third
            ))
        ]

        XCTAssertEqual(
            AppState.visibleSidebarFaviconURLs(from: items, limit: 2),
            [first, second]
        )
        XCTAssertEqual(
            AppState.visibleSidebarFaviconURLs(from: items, limit: 8),
            [first, second, third]
        )
    }

    private func restore(_ value: Any?, key: String, defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
