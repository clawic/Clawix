import SwiftUI
import AppKit

struct RescueRepairSidebarButton: View {
    let summary: RescueRepairStatusSummary
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                LucideIcon.auto("circle-alert", size: 10.5)
                    .frame(width: 15)
                    .foregroundColor(iconColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(summary.title)
                        .font(BodyFont.system(size: 13.5, wght: 500))
                        .foregroundColor(Color(white: 0.92))
                    Text(summary.detail)
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Color(white: 0.64))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if summary.pendingCount > 0 {
                    Text("\(summary.pendingCount)")
                        .font(BodyFont.system(size: 11, wght: 600))
                        .foregroundColor(Color(white: 0.94))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovered ? Color.white.opacity(0.035) : Color.white.opacity(0.018))
            )
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
        .accessibilityLabel("\(summary.title), \(summary.detail)")
    }

    private var iconColor: Color {
        switch summary.mode {
        case .diagnosticsOnly: return Color(red: 1.0, green: 0.60, blue: 0.38)
        case .ephemeralChat: return Color(red: 0.92, green: 0.70, blue: 0.34)
        case .degraded: return Color(red: 0.78, green: 0.78, blue: 0.78)
        case .normal: return Color(white: 0.78)
        }
    }
}


// MARK: - New project popup (start blank / use existing folder)


// MARK: - Settings bottom button (opens account popover above it)


// MARK: - Settings account popover (anchored above the settings button)


// MARK: - Usage limits section

/// Toggleable section for usage limits inside the account popover. Default
/// collapsed; the chevron toggles visibility instantly via SwiftUI's
/// conditional rendering (no height measurement, so it works regardless
/// of when `appState.rateLimits` lands relative to the popover opening).
/// Reads `appState.rateLimits`, which the backend populates via
/// `account/rateLimits/read` at boot and refreshes through
/// `account/rateLimits/updated`.


// MARK: - SidebarButton


// MARK: - ComposeIcon


// MARK: - SectionDisclosureChevron

/// Tunables for collapsible sidebar sections. The chevron rotation and
/// section height share the same spring so the disclosure feels like a
/// single physical gesture.

/// Hover fade with an optional delay only on appear; on disappear the
/// fade is immediate so a group of staggered icons clears at once.


/// Disclosure chevron used by collapsible sidebar section headers
/// (Pinned, All chats, No project, Projects). Rotates with its own
/// spring curve so the rotation reads as physical even when the caller
/// uses a different animation for layout. The hover-brightening is
/// driven from `CollapsibleSectionLabel`, so the title and chevron
/// share one hover region instead of lighting up independently.

/// Title + chevron pair used by collapsible sidebar section headers.
/// Owns one hover state so the label and chevron brighten together,
/// matching the dim/brighten treatment of the header action icons.
/// Optional `leadingIcon` mirrors the icon column of the top sidebar
/// buttons (`New chat`, `Search`); when supplied, a 14x14 slot is laid
/// out before the title so headers visually rhyme with those rows.

/// Collapsible section header used for Pinned, "Chats with no project",
/// Archived, and Tools. Owns its own row-wide hover so the label, chevron
/// and hairlines all light up together when the pointer enters anywhere
/// inside the row, including the hairline tails — not just the inner
/// text+chevron region.
///
/// Optionally renders a single trailing hover icon (used by Pinned for
/// the per-project filter funnel). The icon shares the staggered fade
/// timing of the project header's icon group so the two filter
/// affordances feel like the same control across the sidebar.

/// Hairline that flanks an expanded section title (left + right). Sits
/// vertically centered with the text and grows outward from the word so
/// the open state reads as a labeled separator. `anchor` controls the
/// scale origin: `.trailing` for the left hairline (grows leftward away
/// from the title), `.leading` for the right hairline. Fade-in matches
/// the section expand timing.

// MARK: - PinnedIcon

/// Sidebar header icon button that dims by default and brightens on hover,
/// mirroring the `PinIcon` pattern used in chat rows.


// MARK: - RecentChatRow (runtime-backed chats)


/// Action callbacks the row needs but doesn't own. Held externally so the
/// row can drop `@EnvironmentObject var appState` and become `Equatable`:
/// SwiftUI then short-circuits body re-evaluation when nothing in the row's
/// data inputs changed, even if some other slice of `AppState` did. Each
/// callback captures `appState` (and the chat id) at construction time on
/// the parent side; the parent rebuilds them on demand whenever the row
/// re-evaluates.

/// Free-function factory: kept out of `SidebarView` so other sidebar
/// containers (e.g. `PinnedReorderableList`) can build the same callbacks
/// from their own `appState` reference without reaching back into the
/// outer view.
@MainActor
func makeRecentChatCallbacks(appState: AppState, chat: Chat, archived: Bool) -> RecentChatRowCallbacks {
    let chatId = chat.id
    let chatSnapshot = chat
    let currentSnapshot: () -> Chat = {
        appState.chat(byId: chatId) ?? chatSnapshot
    }
    return RecentChatRowCallbacks(
        onSelect: { appState.navigate(to: .chat(chatId)) },
        onArchive: { appState.archiveChat(chatId: chatId) },
        onUnarchive: { appState.unarchiveChat(chatId: chatId) },
        onTogglePin: { appState.togglePin(chatId: chatId) },
        onRename: { appState.pendingRenameChat = currentSnapshot() },
        onToggleUnread: { appState.toggleChatUnread(chatId: chatId) },
        onOpenInFinder: {
            guard let cwd = currentSnapshot().cwd, !cwd.isEmpty else { return }
            let path = (cwd as NSString).expandingTildeInPath
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        },
        onCopyWorkingDirectory: {
            guard let cwd = currentSnapshot().cwd, !cwd.isEmpty else { return }
            copySidebarStringToPasteboard(cwd)
        },
        onCopySessionId: {
            guard let id = currentSnapshot().clawixThreadId else { return }
            copySidebarStringToPasteboard(id)
        },
        onCopyDeeplink: {
            guard let id = currentSnapshot().clawixThreadId else { return }
            copySidebarStringToPasteboard("clawix://session/\(id)")
        },
        onForkLocal: {
            _ = appState.forkConversation(chatId: chatId, sourceSnapshot: currentSnapshot())
        },
        onContextMenu: { screenPoint in
            SidebarChatContextMenuPanel.present(
                at: screenPoint,
                chat: currentSnapshot(),
                isArchived: archived,
                appState: appState
            )
        }
    )
}

func copySidebarStringToPasteboard(_ value: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(value, forType: .string)
}


/// Quiet thin ring used in chat rows while a turn is in flight. Replaces the
/// default `ProgressView` so the rotation stays slow and the stroke matches
/// the rest of the sidebar's restrained line work.

// MARK: - ProjectAccordion


/// Footer label appended to a `ProjectAccordion`'s chat list to
/// trigger "Show more" (5 → 10) or "View all" (open the per-project
/// popup). Reads as plain text, not a row: no hover background, no
/// rounded "tab" look. Hover animates the text a notch toward white
/// (still well short of the chat title's 0.94) so the user gets a
/// subtle "this is interactive" hint without it competing with the
/// conversation rows above. The trailing whitespace gives the next
/// project's header a little breathing room.

/// Animated vertical reveal driven by an explicit `targetHeight`. We
/// learned the hard way that `GeometryReader` based measurement misfires
/// when the container is clipped to 0, leaving content invisible. So
/// callers compute the natural height from their content (e.g. row count
/// times row height) and we just animate `frame(height:)` between 0 and
/// that target. `.fixedSize(vertical:)` keeps the content rendered at
/// its true intrinsic height so a slightly off estimate clips a few
/// pixels rather than collapsing rows.

/// Heights used for accordion target-height math. Keep these tight to
/// the actual rendered values so the animation lands cleanly. Re-measure
/// if you change row paddings or fonts.

/// Single-transaction accordion: the frame's height is bound directly
/// to `expanded` and animated via `.animation(_:value:)` so it rides the
/// same render pass as the header's icon-opacity and chevron-rotation
/// animations. An earlier `@State displayHeight` updated from `.onChange`
/// inside its own `withAnimation` ran one frame after the header's
/// animations kicked off, so the icon/chevron faded first while the
/// height stayed at 0 — visually the header looked like it drifted and
/// the chats arrived late "from below" once the second transaction caught
/// up.
///
/// `targetHeight` is a heuristic (row count × estimated row height +
/// section padding) that lands the open-state geometry on the same
/// transaction as the header. A `GeometryReader` measures the actual
/// intrinsic content height and we take `max(targetHeight, measuredHeight)`
/// so the floor is always the real content size. Without this, line-height
/// drift between the heuristic and the rendered text (Archived at 15+ rows)
/// clipped the last row because `.clipped()` honours `targetHeight`, not
/// intrinsic height.
///
/// `measuredHeight` follows the content size in both directions. An earlier
/// version only ratcheted up (`if newH > measuredHeight`), which left a
/// stale tall frame after rows were removed (unpinning, moving a chat into
/// a folder) — the section "remembered" its old maximum height and the
/// gap stayed open until something forced a re-measurement.


/// Animated vertical reveal: a hidden twin always renders at its intrinsic
/// height to drive `measuredHeight`, the visible tree renders at full
/// opacity, and only the outer frame animates between 0 and the measured
/// height. Reveal direction comes from the clip alone (top-to-bottom on
/// open, bottom-to-top on close) so it matches the cadence of the simpler
/// `SidebarAccordion`-driven sections like Archived.


// MARK: - PinnedRow


// MARK: - Project row dropdown menu


// MARK: - Organize / Sort menu (funnel button next to the projects header)


/// Three-section dropdown: top-level view mode (Grouped vs Chronological),
/// project sort field (only when grouped), and a `Filter > By project`
/// submenu (only when chronological). The filter row mirrors the
/// hover-reveals-side-panel pattern used in the composer's model picker
/// (`ModelMenuPopup`): hovering the chevron spawns a column to the right
/// with the project filter list, so this popup remains the single entry
/// point for organizing the chat list. Selections persist via the
/// caller's `@AppStorage`-backed bindings; the side panel's per-project
/// toggles flow through the `chronoFilter*` callbacks.


/// Row variant of `OrganizeMenuRow` that ends in a chevron and stays
/// highlighted while its companion side panel is open. Mirrors the
/// chevron row styling used by `ModelMenuChevronRow` in the composer's
/// model picker so the two cascading menus read as the same family.

// MARK: - Pinned filter

/// Distinct buckets present across the loaded pinned chats: each project
/// that has at least one pinned chat, plus a synthetic "no project"
/// entry when any chat has `projectId == nil`. Lives at file scope so
/// the popup type below can name it as a concrete parameter.


/// Per-project visibility filter for the Pinned section. Each row maps
/// to one bucket present across the user's pinned chats (a project, or
/// the synthetic "no project" entry). Toggling a row flips its inclusion
/// in the visible list. The popup also exposes a "Show all" shortcut at
/// the bottom that wipes the entire disabled set in one click — the
/// recovery path when the user filtered down to "nothing visible" and
/// can no longer find the chats they pinned earlier.

/// Toggleable row inside `PinnedFilterPopup`. Active state is shown with
/// a check on the trailing edge and the icon + label rendered at full
/// brightness; inactive rows fade their label and icon so the disabled
/// state reads at a glance even without hovering.

/// Footer row inside `PinnedFilterPopup` for "Show all" / "Hide all"
/// shortcuts. Same hover styling as the toggleable project rows so the
/// footer reads as part of the same list, just with a divider above it.

// MARK: - Drag-and-drop helper

/// Wraps any sidebar row in a drop target that accepts a `Chat.id` UUID
/// carried as plain text by `RecentChatRow`'s `.onDrag`. Renders a soft
/// inset highlight while a drag hovers the wrapper, matching the row /
/// menu hover language used elsewhere in the app.
///
/// `accept` returns whether the drop was actually meaningful (e.g. drop
/// onto a row's own source is rejected) so we don't pretend to handle
/// no-ops.

/// Custom delegate so we can reject project reorder drags before SwiftUI
/// flips `isTargeted`. Project drags carry a `public.url` representation
/// (`clawix-project://<UUID>`); `NSPasteboard` may auto-promote URLs to
/// `public.utf8-plain-text`, so the closure-based `.onDrop(of: [.text])`
/// would otherwise highlight project rows as if they were valid chat
/// drop targets.

// MARK: - Pinned reorderable list

/// Pinned-section list with intra-list drag reordering. The design
/// optimises for stability of the visual feedback during the drag and
/// for an instant, flicker-free placement on drop:
///
/// - On drag start the source row collapses (frame 0, opacity 0) AND the
///   gap is opened at the source's own slot, so the total list height
///   stays constant from frame zero. As the pointer moves to a different
///   slot, only the gap migrates: the list never grows or shrinks.
/// - Each slot zone is one contiguous drop target that includes the gap
///   above the row plus the row itself. Adjacent slot zones touch with
///   no dead band, so moving the pointer between rows can never land in a
///   "no drop target" sliver and bounce the gap off.
/// - `dropExited` does not clear the gap immediately. It schedules a
///   cancelable task; if the next slot's `dropEntered` fires before the
///   delay, the clear is cancelled. If the pointer truly left the list,
///   the gap reverts to the source's own slot (internal drag) or closes
///   (external drag). No flicker between adjacent slots.
/// - `performDrop` applies `reorderPinned` AND clears `draggingId` /
///   `targetIndex` inside a `Transaction(animation: nil)` so the row
///   simply renders at its new index in the next pass. Nothing animates,
///   nothing crossfades, the placement is atomic.
///
/// External drags (e.g. a chat dragged in from a project) are accepted
/// too: the gap opens where it will land, and `reorderPinned` pins it
/// at that position on drop.
/// Mutable bag for per-row window-coord frames. Used at drag-start to
/// anchor the chip relative to the pointer. Stored on a reference type
/// (mutated via `byId = ...`) so the per-frame `onPreferenceChange`
/// writes don't go through `@State` and therefore don't invalidate
/// SwiftUI on every layout pass — the streaming chat publish flood was
/// otherwise running this loop dozens of times per second for nothing.


// MARK: - Pinned drag auto-scroll

/// Weak handle to the surrounding `NSScrollView`. Populated by
/// `EnclosingScrollViewLocator` once SwiftUI drops the locator into
/// the AppKit hierarchy; consumed by `PinnedDragAutoScroller` while a
/// pinned-row drag is active so it can nudge the scroller without
/// going through SwiftUI bindings.
/// Walks up its AppKit superview chain to find the nearest enclosing
/// `NSScrollView` and stashes a weak reference in `box`. Mirrors the
/// trick `ThinScrollerInstaller` uses, but exposes the scroll view to
/// SwiftUI code that needs to drive scrolling imperatively (e.g. the
/// pinned-list drag auto-scroll).

/// 60Hz auto-scroll driver active during a pinned-row drag. Polls
/// `NSEvent.mouseLocation` (still queryable while AppKit's drag
/// session owns the event stream, same trick `DragChipPanel` uses);
/// when the pointer sits inside the top or bottom edge zone of the
/// surrounding scroll view's visible rect, scrolls in that direction
/// with a speed that ramps up the closer the pointer is to the edge.
/// SwiftUI's `.onDrop` keeps firing against whatever slot zone is now
/// under the pointer, so the gap follows the new content and the user
/// can drop on rows that started off screen.
// MARK: - Window-drag inhibitor

/// SwiftUI helper that drops a real NSView into the row, just so AppKit
/// has something whose `mouseDownCanMoveWindow` returns `false` to find at
/// the click point. Without this, the window's `isMovableByWindowBackground
/// = true` setting (see `App.swift`) causes mouseDown on a row to start a
/// window drag instead of letting SwiftUI's `.onDrag` initiate the chat
/// drag-and-drop.
///
/// We DO want the view to participate in hit-testing (otherwise AppKit
/// falls through to the SwiftUI host, which doesn't override
/// `mouseDownCanMoveWindow`). We just don't want to consume the click:
/// `mouseDown` is forwarded to the next responder so SwiftUI's gesture
/// recognizers (`.onTapGesture`, `.onDrag`) on the parent SwiftUI host
/// still fire normally.
/// Three stacked horizontal bars with a steep length progression
/// (100% / ~58% / ~29%) used as the "organize / filter chats" affordance in
/// the sidebar header. Replaces SF Symbol `line.3.horizontal.decrease`, whose
/// progression was too gentle to read as a hierarchy at this size.


/// Counterpart to `WindowDragInhibitor`: a transparent NSView whose only
/// job is to return `mouseDownCanMoveWindow = true`. Painted under the top
/// chrome strip so the user can grab and move the window from anywhere in
/// that band, even though `isMovableByWindowBackground` is off everywhere
/// else. Buttons inside the strip keep working: AppKit's hit test finds
/// the NSButton (or other control) on top of this view, and controls
/// return `false` from `mouseDownCanMoveWindow` by default.

// MARK: - DragChipPanel

/// Borderless `NSPanel` that shows a SwiftUI chip following the pointer
/// during a pinned-row drag. We hand macOS's drag preview a 1pt
/// transparent view (so the system's ~500ms settle animation has nothing
/// visible to fade) and render the user-facing chip ourselves here so we
/// can hide it the instant the drop lands. A 60Hz timer polls
/// `NSEvent.mouseLocation`; that is queryable even while AppKit's drag
/// session owns the event stream and `NSEvent.addLocalMonitorForEvents`
/// is silenced.
/// Bubbles each pinned row's frame (window coords, top-left origin) up
/// so `PinnedReorderableList` can compute the pointer's offset within
/// the row at drag start. The chip rendered in `DragChipPanel` uses
/// that offset to anchor the pointer to the same point of the chip the
/// user originally clicked.

/// Visual content of the drag chip. Mirrors a hovered `RecentChatRow`
/// (pin icon + title + archive icon) so the user reads it as the exact
/// line they just picked up. Width is the row's measured width, padding
/// and corner radius mirror `RecentChatRow.body`, and the background
/// pairs the sidebar's `VisualEffectBlur` with the same hover overlay
/// (`Color.white.opacity(0.035)`) so the chip composites against the
/// desktop the same way the row composites against the sidebar.
/// No stroke; any extra outline shifts the perceived width away from
/// the row underneath.

// MARK: - Project drag-reorder ("Custom" sort mode)

/// Visual content of the project drag chip. Mirrors the project header
/// row (folder icon + name) so the user reads it as the same line they
/// just picked up. Same chrome as `DragChipView` so chat and project
/// chips composite identically over the desktop background.

/// Bubbles each project row's frame (window coords, top-left origin)
/// up so `ProjectReorderableList` can compute the pointer's offset
/// within the row at drag start (mirrors `PinnedRowFrameKey`).

/// Reference-type bag for per-row frames. Same trick as
/// `PinnedRowFrameStore`: mutating `byId` doesn't go through `@State`
/// so the per-frame preference firehose during accordion expansion
/// doesn't invalidate SwiftUI on every layout pass.

/// File-private constant outside the generic type — Swift forbids
/// static stored properties on generic types.
let projectReorderMoveAnimation: Animation = .easeInOut(duration: 0.20)

/// Wraps the projects ForEach with custom drag-reorder. Active only when
/// `projectSortMode == .custom`; in other modes the parent renders the
/// rows directly so dragging is impossible (it would conflict with the
/// computed sort). Mirrors `PinnedReorderableList`'s structure: gap
/// placeholders between rows, a borderless `DragChipPanel` that follows
/// the pointer, and edge auto-scroll via `PinnedDragAutoScroller`.


/// `clawix-project://<UUID>` puts the UUID in the host slot. macOS
/// canonicalises hostnames to lowercase, but `UUID(uuidString:)` is
/// case-insensitive. Falls back to the first path component for the
/// (rare) case where the URL parser stripped the host.
func projectId(from url: URL) -> UUID? {
    if let host = url.host, let uuid = UUID(uuidString: host) {
        return uuid
    }
    let trimmed = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return UUID(uuidString: trimmed)
}

// MARK: - Tools section: filter popup + reorderable list


/// Popup that mirrors `PinnedFilterPopup` but operates on the static tools
/// catalog rather than per-project buckets. Each row toggles a tool's
/// presence in the sidebar list; the footer offers `Show all` / `Hide all`
/// shortcuts so the user can recover from "I hid everything" in one click.


// MARK: - Tools reorderable list

/// Bubbles each tool row's frame (window coords, top-left origin) up so
/// `ToolsReorderableList` can compute the pointer's offset within the row
/// at drag start (mirrors `ProjectRowFrameKey`, keyed by tool id rather
/// than UUID).


/// File-private constant outside the type so it stays consistent with
/// the existing `projectReorderMoveAnimation`.
let toolReorderMoveAnimation: Animation = .easeInOut(duration: 0.20)

/// Drag-reorderable list for the Tools section. Mirrors the structure of
/// `ProjectReorderableList`: gap placeholders between rows, a borderless
/// `DragChipPanel` that follows the pointer while AppKit's drag preview
/// renders a 1pt transparent stand-in (no settle fade on drop). External
/// drags (chats, projects) are rejected because the drop delegate only
/// accepts the `clawix-tool` URL scheme.

/// Drop delegate scoped to the `clawix-tool://<id>` URL scheme so chat /
/// project drags never highlight tool slot zones.

/// Display-only tool row used inside `ToolsReorderableList`. Wraps
/// `SecretsToolRow` for the secrets entry and `DatabaseToolRow` for
/// everything else, so the visual treatment stays identical to the
/// pre-reorder design.

/// Mirror of `DatabaseToolRow` that renders the brand mark as the
/// row icon. Used by the `Agents` sidebar entry so the entrance point
/// for the agent-roster surface carries the Clawix identity.

/// Visual content of the tool drag chip. Matches the look of the row
/// underneath (icon + title) inside the same translucent capsule used by
/// `DragChipView` / `ProjectDragChipView` so chat, project and tool
/// chips composite identically over the desktop.
