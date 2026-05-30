import SwiftUI

/// Top-level "Agents" section in the sidebar. Peer of Tools / Apps /
/// Design, built from the same canonical chrome: a `BasicSectionHeader`
/// plus one nav row per agent the user has on disk, each carrying the
/// agent's tinted avatar in the standard 15pt icon column. Tapping a row
/// deep-links to that agent's detail; the header's hover-reveal
/// affordance opens the full Agents home.
///
/// Pulled out of the Tools catalog so agents read as first-class citizens
/// of the sidebar (like Apps), and so the list reflects the live
/// `AgentStore` rather than a single static "Agents" entry. The body
/// rides a `SidebarAccordion` so its open/close matches the other
/// sections, and the leading icon collapses into the section hairline on
/// expand exactly like Pinned / Archived.
struct AgentsSidebarSection: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var store: AgentStore = .shared

    @AppStorage(ClawixPersistentSurfaceKeys.sidebarAgentsExpanded, store: SidebarPrefs.store)
    private var expanded: Bool = true

    /// Cap visible rows in the sidebar. The header's "All agents" entry
    /// surfaces the full catalog when the user has more than this.
    private static let visibleLimit = 8

    /// Estimated nav-row height for the accordion target. Slightly under
    /// the rendered height so the measured height wins and the open state
    /// lands on the content's exact size (matches `AppsSidebarSection`).
    private let rowHeight: CGFloat = 28

    private var visibleAgents: [Agent] {
        Array(store.agents.prefix(Self.visibleLimit))
    }

    private var hasOverflow: Bool {
        store.agents.count > Self.visibleLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BasicSectionHeader(
                title: "Agents",
                expanded: $expanded,
                leadingIcon: AnyView(ClawixLogoIcon(size: 16)),
                controlId: "sidebar.section.agents",
                controlLabel: "Agents",
                trailingIcon: AnyView(allAgentsButton)
            )
            SidebarAccordion(expanded: expanded, targetHeight: bodyHeight) {
                VStack(alignment: .leading, spacing: 0) {
                    if visibleAgents.isEmpty {
                        emptyHint
                    } else {
                        ForEach(visibleAgents) { agent in
                            AgentsSidebarRow(
                                agent: agent,
                                isSelected: isSelected(agent),
                                onOpen: { appState.navigate(to: .agentDetail(id: agent.id)) }
                            )
                        }
                        if hasOverflow {
                            allAgentsRow
                        }
                    }
                    Color.clear.frame(height: SidebarRowMetrics.sectionEdgePadding)
                }
                .padding(.leading, 8)
            }
        }
    }

    private var bodyHeight: CGFloat {
        let rows = visibleAgents.isEmpty ? 1 : (visibleAgents.count + (hasOverflow ? 1 : 0))
        return CGFloat(rows) * rowHeight + SidebarRowMetrics.sectionEdgePadding
    }

    /// Hover-reveal trailing affordance, mirroring the Apps "All apps"
    /// grid so every section header shares one icon language.
    private var allAgentsButton: some View {
        HeaderHoverIcon(tooltip: "All agents") {
            appState.navigate(to: .agentsHome)
        } label: { color in
            LucideIcon.auto("square.grid.2x2", size: 13)
                .foregroundColor(color)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
    }

    private var emptyHint: some View {
        Text("No agents yet")
            .font(BodyFont.system(size: 13.5, wght: 500))
            .foregroundColor(Color.gray(light: 0.54, dark: 0.40))
            .padding(.leading, 34)
            .padding(.vertical, 4)
    }

    private var allAgentsRow: some View {
        AgentsOverflowRow(count: store.agents.count) {
            appState.navigate(to: .agentsHome)
        }
    }

    private func isSelected(_ agent: Agent) -> Bool {
        if case let .agentDetail(id) = appState.currentRoute, id == agent.id { return true }
        return false
    }
}

/// "All agents (N)" overflow entry. Canonical nav row metrics; reads as a
/// quieter sibling of the agent rows above it.
private struct AgentsOverflowRow: View {
    let count: Int
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 11) {
                LucideIcon.auto("ellipsis.circle", size: 12.5)
                    .frame(width: 15, height: 15)
                    .foregroundColor((hovered ? Color.gray(light: 0.14, dark: 0.92) : Color.gray(light: 0.27, dark: 0.78)))
                Text("All agents (\(count))")
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

/// One row inside the sidebar Agents section. Canonical nav-row metrics
/// with the agent's tinted avatar in the standard 15pt icon column.
private struct AgentsSidebarRow: View {
    let agent: Agent
    let isSelected: Bool
    let onOpen: () -> Void

    @State private var hovered: Bool = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 11) {
                AgentAvatarBadge(avatar: agent.avatar, size: 15)
                Text(agent.name)
                    .font(BodyFont.system(size: 13.5, wght: 500))
                    .foregroundColor(isSelected ? .white : Color.gray(light: 0.14, dark: 0.92))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if agent.isBuiltin {
                    Text("Built-in")
                        .font(BodyFont.system(size: 9.5, wght: 600))
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
    }

    private var rowBackground: Color {
        if isSelected { return Color.overlay(0.06) }
        if hovered    { return Color.overlay(0.035) }
        return .clear
    }
}
