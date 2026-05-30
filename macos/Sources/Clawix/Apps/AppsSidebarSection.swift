import SwiftUI

/// Top-level "Apps" section in the sidebar. Peer of Pinned / Projects /
/// Tools / Archived, and built from the same canonical chrome: a
/// `BasicSectionHeader` plus nav rows whose metrics match
/// `SidebarButton` / `DatabaseToolRow` (spacing 11, 15pt icon column,
/// 13.5/500 label, 10/6 padding, radius 9, 0.78 → 0.92 → white tones).
/// The body rides a `SidebarAccordion` so its open/close matches the
/// other sections.
///
/// Lives outside `SidebarView.swift` so the sidebar file (~5k lines)
/// doesn't grow another section worth of state. Glues into the
/// existing `SidebarPrefs` `UserDefaults` suite for the expansion flag.
struct AppsSidebarSection: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var appsStore: AppsStore = .shared

    @AppStorage(ClawixPersistentSurfaceKeys.sidebarAppsExpanded, store: SidebarPrefs.store)
    private var expanded: Bool = true
    @State private var pendingDelete: AppRecord?

    /// Cap visible rows in the sidebar. The header's "All apps" entry
    /// surfaces the full catalog when the user has more than this.
    private static let visibleLimit = 8

    /// Estimated nav-row height for the accordion target. Slightly under
    /// the rendered height so the measured height wins and the open state
    /// lands on the content's exact size (matches `ToolsReorderableList`).
    private let rowHeight: CGFloat = 28

    private var visibleApps: [AppRecord] {
        Array(appsStore.sortedApps.prefix(Self.visibleLimit))
    }

    private var hasOverflow: Bool {
        appsStore.apps.count > Self.visibleLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BasicSectionHeader(
                title: "Apps",
                expanded: $expanded,
                leadingIcon: AnyView(BlocksIcon(size: 16)),
                controlId: "sidebar.section.apps",
                controlLabel: "Apps",
                trailingIcon: AnyView(allAppsButton)
            )
            SidebarAccordion(expanded: expanded, targetHeight: bodyHeight) {
                VStack(alignment: .leading, spacing: 0) {
                    if visibleApps.isEmpty {
                        emptyHint
                    } else {
                        ForEach(visibleApps) { record in
                            AppsSidebarRow(
                                record: record,
                                isSelected: isSelected(record),
                                onOpen: { appState.navigate(to: .app(record.id)) },
                                onTogglePin: { appsStore.togglePinned(record) },
                                onDelete: { pendingDelete = record }
                            )
                        }
                        if hasOverflow {
                            allAppsRow
                        }
                    }
                    Color.clear.frame(height: SidebarRowMetrics.sectionEdgePadding)
                }
                .padding(.leading, 8)
            }
        }
        .alert(item: $pendingDelete) { record in
            Alert(
                title: Text("Delete \"\(record.name)\"?"),
                message: Text("The app folder will be removed from disk. This cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    try? appsStore.delete(record)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var bodyHeight: CGFloat {
        let rows = visibleApps.isEmpty ? 1 : (visibleApps.count + (hasOverflow ? 1 : 0))
        return CGFloat(rows) * rowHeight + SidebarRowMetrics.sectionEdgePadding
    }

    /// Hover-reveal trailing affordance, mirroring the Pinned funnel /
    /// Tools filter so every section header shares one icon language.
    private var allAppsButton: some View {
        HeaderHoverIcon(tooltip: "All apps") {
            appState.navigate(to: .appsHome)
        } label: { color in
            LucideIcon.auto("square.grid.2x2.fill", size: 13)
                .foregroundColor(color)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
    }

    private var emptyHint: some View {
        Text("Ask the agent to build one")
            .font(BodyFont.system(size: 13.5, wght: 500))
            .foregroundColor(Color.gray(light: 0.54, dark: 0.40))
            .padding(.leading, 34)
            .padding(.vertical, 4)
    }

    private var allAppsRow: some View {
        AppsOverflowRow(count: appsStore.apps.count) {
            appState.navigate(to: .appsHome)
        }
    }

    private func isSelected(_ record: AppRecord) -> Bool {
        if case let .app(id) = appState.currentRoute, id == record.id { return true }
        return false
    }
}

/// "All apps (N)" overflow entry. Canonical nav row metrics; reads as a
/// quieter sibling of the app rows above it.
private struct AppsOverflowRow: View {
    let count: Int
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 11) {
                LucideIcon.auto("ellipsis.circle", size: 12.5)
                    .frame(width: 15, height: 15)
                    .foregroundColor((hovered ? Color.gray(light: 0.14, dark: 0.92) : Color.gray(light: 0.27, dark: 0.78)))
                Text("All apps (\(count))")
                    .font(BodyFont.system(size: 13.5, wght: 500))
                    .foregroundColor(Color.gray(light: 0.14, dark: 0.92))
                    .lineLimit(1)
                Spacer(minLength: 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovered ? Color.overlay(0.035) : .clear)
            )
            .animation(.easeOut(duration: 0.12), value: hovered)
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
    }
}

/// One row inside the sidebar Apps section. Canonical nav-row metrics with
/// the app's colored identity chip in the standard 15pt icon column, plus
/// a pin indicator and a pin/delete context menu.
private struct AppsSidebarRow: View {
    let record: AppRecord
    let isSelected: Bool
    let onOpen: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var hovered: Bool = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 11) {
                iconChip
                Text(record.name)
                    .font(BodyFont.system(size: 13.5, wght: 500))
                    .foregroundColor(isSelected ? .white : Color.gray(light: 0.14, dark: 0.92))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if record.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color.gray(light: 0.46, dark: 0.5))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(rowBackground)
            )
            .animation(.easeOut(duration: 0.12), value: hovered)
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
        .contextMenu {
            Button(record.pinned ? "Unpin from sidebar" : "Pin to sidebar", action: onTogglePin)
            Divider()
            Button("Delete app", role: .destructive, action: onDelete)
        }
    }

    private var rowBackground: Color {
        if isSelected { return Color.overlay(0.06) }
        if hovered    { return Color.overlay(0.035) }
        return .clear
    }

    private var iconChip: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .fill(chipColor)
            if !record.icon.isEmpty {
                Text(record.icon)
                    .font(.system(size: 10.5))
            } else {
                Text(initials)
                    .font(BodyFont.system(size: 8.5, wght: 700))
                    .foregroundColor(Color.overlay(0.92))
            }
        }
        .frame(width: 15, height: 15)
    }

    private var initials: String {
        let parts = record.name.split(separator: " ", maxSplits: 1)
        if parts.count == 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(record.name.prefix(2)).uppercased()
    }

    private var chipColor: Color {
        if let parsed = Color(appsHex: record.accentColor) {
            return parsed
        }
        var hash: UInt64 = 0
        for byte in record.slug.utf8 { hash = hash &* 131 &+ UInt64(byte) }
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.55)
    }
}
