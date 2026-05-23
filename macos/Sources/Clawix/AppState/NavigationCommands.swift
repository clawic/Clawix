import AppKit
import SwiftUI

// Keyboard-driven chat + view navigation backing the menu commands:
// Previous/Next chat (⇧⌘[ / ⇧⌘]), Back/Forward (⌘[ / ⌘]), Go to chat 1-9
// (⌘1–⌘9) and the recently-viewed cycle (⌃Tab / ⌃⇧Tab).
extension AppState {
    /// Chat ids in the order the sidebar shows them: pinned chats first (in
    /// their manual `pinnedOrder`, with any pinned-but-unordered chats kept in
    /// array order), then the rest in `chats` order (already updatedAt-desc).
    /// Drives Previous/Next chat and the ⌘1–⌘9 slots so keyboard motion
    /// matches what the user sees.
    var navigableChatIds: [UUID] {
        let all = chats
        let pinnedById = Dictionary(uniqueKeysWithValues: all.filter { $0.isPinned }.map { ($0.id, $0) })
        var pinned: [UUID] = []
        for id in pinnedOrder where pinnedById[id] != nil {
            pinned.append(id)
        }
        for chat in all where chat.isPinned && !pinned.contains(chat.id) {
            pinned.append(chat.id)
        }
        let rest = all.filter { !$0.isPinned }.map(\.id)
        return pinned + rest
    }

    /// Move to the chat before/after the current one in the sidebar order,
    /// wrapping around the ends. With no chat selected, jumps to the first
    /// (forward) or last (backward) chat.
    func goToAdjacentChat(forward: Bool) {
        let ids = navigableChatIds
        guard !ids.isEmpty else { return }
        guard let current = currentChatId, let idx = ids.firstIndex(of: current) else {
            navigate(to: .chat(forward ? ids[0] : ids[ids.count - 1]))
            return
        }
        let next = ((idx + (forward ? 1 : -1)) % ids.count + ids.count) % ids.count
        navigate(to: .chat(ids[next]))
    }

    /// Jump to the chat in 1-based slot `slot` (⌘1–⌘9). No-ops when the slot
    /// is out of range.
    func goToChatSlot(_ slot: Int) {
        let ids = navigableChatIds
        guard slot >= 1, slot <= ids.count else { return }
        navigate(to: .chat(ids[slot - 1]))
    }

    // MARK: - View history (Back / Forward)

    /// Called from `currentRoute.didSet`. Pushes the route we left onto the
    /// back stack and records chat visits for the MRU cycle. Skipped while a
    /// history/cycle replay is in flight.
    func recordNavigationHistory(oldValue: SidebarRoute) {
        if isNavigatingViaHistory { return }
        if oldValue != currentRoute {
            routeBackStack.append(oldValue)
            if routeBackStack.count > 50 { routeBackStack.removeFirst() }
            routeForwardStack.removeAll()
        }
        if case let .chat(id) = currentRoute, !isCyclingRecentChats {
            recentlyViewedChatIds.removeAll { $0 == id }
            recentlyViewedChatIds.insert(id, at: 0)
            if recentlyViewedChatIds.count > 50 { recentlyViewedChatIds.removeLast() }
            recentCycleIndex = nil
        }
    }

    var canNavigateBack: Bool { !routeBackStack.isEmpty }
    var canNavigateForward: Bool { !routeForwardStack.isEmpty }

    func navigateRouteBack() {
        guard let previous = routeBackStack.popLast() else { return }
        let resolved = previous.visibleRoute(isVisible: FeatureFlags.shared.isVisible)
        isNavigatingViaHistory = true
        routeForwardStack.append(currentRoute)
        currentRoute = resolved
        isNavigatingViaHistory = false
    }

    func navigateRouteForward() {
        guard let next = routeForwardStack.popLast() else { return }
        let resolved = next.visibleRoute(isVisible: FeatureFlags.shared.isVisible)
        isNavigatingViaHistory = true
        routeBackStack.append(currentRoute)
        currentRoute = resolved
        isNavigatingViaHistory = false
    }

    // MARK: - Recently-viewed chat cycle (⌃Tab / ⌃⇧Tab)

    /// Step through recently viewed chats. The cycle pointer persists across
    /// consecutive presses (so holding ⌃ and tapping Tab walks the list) and
    /// resets the moment any other chat navigation happens.
    func cycleRecentlyViewedChat(forward: Bool) {
        let ids = recentlyViewedChatIds.filter { chat(byId: $0) != nil }
        guard !ids.isEmpty else { return }
        let start = recentCycleIndex ?? 0
        let next = ((start + (forward ? 1 : -1)) % ids.count + ids.count) % ids.count
        isCyclingRecentChats = true
        navigate(to: .chat(ids[next]))
        recentCycleIndex = next
        isCyclingRecentChats = false
    }
}
