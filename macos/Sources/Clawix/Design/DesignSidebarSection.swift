import SwiftUI

/// Top-level "Design" section in the sidebar. Peer of Apps / Pinned /
/// Projects / Tools / Archived, built from the canonical chrome: a
/// `BasicSectionHeader` plus nav rows whose metrics match
/// `SidebarButton` / `DatabaseToolRow` (spacing 11, 15pt icon column,
/// 13.5/500 label, 10/6 padding, radius 9, 0.78 → 0.92 → white tones).
/// Exposes three entry points: Styles (saved design recipes), Templates
/// (parametrised pieces by category) and References (inspiration library).
struct DesignSidebarSection: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var store: DesignStore = .shared

    @AppStorage(ClawixPersistentSurfaceKeys.sidebarDesignExpanded, store: SidebarPrefs.store)
    private var expanded: Bool = true

    /// Estimated nav-row height for the accordion target. Slightly under
    /// the rendered height so the measured height wins and the open state
    /// lands on the content's exact size (matches `ToolsReorderableList`).
    private let rowHeight: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BasicSectionHeader(
                title: "Design",
                expanded: $expanded,
                leadingIcon: AnyView(LucideIcon.auto("paintbrush", size: 13))
            )
            SidebarAccordion(
                expanded: expanded,
                targetHeight: 3 * rowHeight + SidebarRowMetrics.sectionEdgePadding
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    DesignSidebarRow(
                        title: "Styles",
                        icon: "paintpalette",
                        count: store.styles.count,
                        isSelected: isSelected(.designStylesHome),
                        onOpen: { appState.navigate(to: .designStylesHome) }
                    )
                    DesignSidebarRow(
                        title: "Templates",
                        icon: "rectangle.grid.2x2",
                        count: store.templates.count,
                        isSelected: isSelected(.designTemplatesHome),
                        onOpen: { appState.navigate(to: .designTemplatesHome) }
                    )
                    DesignSidebarRow(
                        title: "References",
                        icon: "books.vertical",
                        count: store.references.count,
                        isSelected: isSelected(.designReferencesHome),
                        onOpen: { appState.navigate(to: .designReferencesHome) }
                    )
                    Color.clear.frame(height: SidebarRowMetrics.sectionEdgePadding)
                }
                .padding(.leading, 8)
            }
        }
    }

    private func isSelected(_ route: SidebarRoute) -> Bool {
        appState.currentRoute == route
    }
}

private struct DesignSidebarRow: View {
    let title: String
    let icon: String
    let count: Int
    let isSelected: Bool
    let onOpen: () -> Void

    @State private var hovered: Bool = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 11) {
                LucideIcon.auto(icon, size: 12.5)
                    .frame(width: 15, height: 15)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(BodyFont.system(size: 13.5, wght: 500))
                    .foregroundColor(labelColor)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if count > 0 {
                    Text("\(count)")
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Color(white: 0.55))
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
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var iconColor: Color {
        if isSelected { return .white }
        return Color(white: hovered ? 0.92 : 0.78)
    }

    private var labelColor: Color {
        isSelected ? .white : Color(white: 0.92)
    }

    private var rowBackground: Color {
        if isSelected { return Color.white.opacity(0.06) }
        if hovered    { return Color.white.opacity(0.035) }
        return .clear
    }
}
