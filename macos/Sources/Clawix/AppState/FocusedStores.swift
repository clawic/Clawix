import Combine
import Foundation
import SwiftUI

// MARK: - Focused stores split off the AppState god-object (P4)
//
// These child stores hold slices of state that have NOTHING to do with the two
// hot charter surfaces (the sidebar and the open session). They live as `let`
// children on `AppState` (the same shape as `composer`/`meshStore`), and they
// deliberately DO NOT forward their `objectWillChange` to `AppState`.
//
// Consequence (the P4 contract): a write to one of these stores fires only that
// store's `objectWillChange`. It never fans `AppState.objectWillChange` out to
// the ~90 `@EnvironmentObject` observers, so the sidebar bodies, the session
// presentation layer, and the chat surfaces are not re-evaluated by an unrelated
// browser-chrome / rate-limit / search write.
//
// `AppState` keeps same-named computed forwarders for source compatibility, so
// existing `appState.rateLimits` / `appState.searchQuery` call sites compile
// unchanged. The forwarders read/write the child store, which means the value
// still round-trips, but the publish stays scoped to the child. Views that need
// to re-render on these values observe the child store directly.

/// Rate-limit + metered-bucket status reported by the backend. Pure status
/// payload; no chat/sidebar surface derives from it, so it has no business
/// living on the god-object's publish chain.
@MainActor
final class RateLimitStore: ObservableObject {
    /// Snapshot of the user's primary/secondary rate-limit windows as reported
    /// by the backend. nil while the initial fetch is in flight or when the
    /// backend declined to answer.
    @Published var rateLimits: RateLimitSnapshot? = nil
    /// Per-bucket rate-limit snapshots keyed by metered `limit_id`. Empty when
    /// the backend doesn't surface a per-bucket view.
    @Published var rateLimitsByLimitId: [String: RateLimitSnapshot] = [:]
}

/// Conversation search state: the query, the merged result rows, and the route
/// each row navigates to. Only the search surface consumes this; routing it
/// through the god-object meant every keystroke fanned out to the whole app.
@MainActor
final class SearchStore: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var searchResults: [String] = []
    @Published var searchResultRoutes: [String: SidebarRoute] = [:]
}

/// Mid-turn plan state keyed by chat: the agent's `update_plan` checklist per
/// chat, and the per-chat `requestUserInput` question awaiting an answer. Only
/// the thread-summary panel (the Progress checklist) and the composer's plan
/// question card consume these; routing them through the god-object meant a plan
/// update for chat A fanned `AppState.objectWillChange` out to every observer,
/// re-deriving chat B's session and the whole sidebar. They live on a focused
/// store so a plan change publishes only `planStore.objectWillChange`, scoped to
/// the surfaces that actually read it.
@MainActor
final class PlanStore: ObservableObject {
    /// Latest plan (from the agent's `update_plan` tool) per chat, parsed from
    /// the rollout on hydration. Drives the thread-summary panel's Progress
    /// checklist. Last `update_plan` wins.
    @Published var planByChat: [UUID: [PlanStep]] = [:]
    /// Per-chat plan-mode questions awaiting an answer. Set when the backend
    /// sends `item/tool/requestUserInput`; cleared on submit / dismiss / turn
    /// completion.
    @Published var pendingPlanQuestions: [UUID: PendingPlanQuestion] = [:]
}

/// Type-ahead queue keyed by chat: follow-up messages the user lined up while a
/// chat's turn was still running. Only the composer's queued-rows surface reads
/// it, so a queue change for chat A has no business re-deriving chat B's session
/// or the sidebar. Lives on a focused store so an enqueue/dequeue publishes only
/// `queueStore.objectWillChange`.
@MainActor
final class QueueStore: ObservableObject {
    /// Follow-up messages queued per chat. Each entry is dispatched, oldest
    /// first, when the chat's current turn completes cleanly.
    @Published var queuedMessages: [UUID: [QueuedMessage]] = [:]
}

/// Browser chrome state that lives outside the per-tab controller observation
/// chain (favicon memory, per-tab loading spinners, sampled page background
/// colours, and the one-shot reload / command / focus signals). The chat and
/// sidebar surfaces never read any of this, so it has no reason to invalidate
/// them.
@MainActor
final class BrowserChromeStore: ObservableObject {
    /// Cross-tab favicon memory keyed by the registrable host. Persisted to
    /// UserDefaults under `HostFavicons` so it survives relaunches.
    @Published var hostFavicons: [String: URL] = [:]
    /// One-shot signal consumed by `BrowserView` to reload the active web view.
    @Published var pendingReloadTabId: UUID? = nil
    /// One-shot command the menu / keyboard shortcuts dispatch toward the active
    /// browser tab. Counter-tagged so two same-action presses fire as distinct
    /// events.
    @Published var pendingBrowserCommand: BrowserCommandRequest? = nil
    /// Tagged signal for the URL field to grab focus and pre-fill with the full
    /// URL.
    @Published var pendingFocusURLBar: BrowserFocusURLBarRequest? = nil
    /// Per-tab "is the WKWebView currently navigating" mirror for the tab-strip
    /// pills, which live outside the controller's observation chain.
    @Published var browserTabsLoading: Set<UUID> = []
    /// Per-web-tab live page background colour sampled from the bottom-left pixel
    /// of each browser webview.
    @Published var browserPageBackgroundColors: [UUID: Color] = [:]
}
