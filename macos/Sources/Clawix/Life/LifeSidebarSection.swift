import SwiftUI

/// Sidebar section that exposes the user-enabled Life verticals. Peer of
/// `DesignSidebarSection` / `AppsSidebarSection` and, like the rest of the
/// sidebar, built from the canonical chrome: a `BasicSectionHeader` and
/// nav rows whose metrics match `SidebarButton` / `DatabaseToolRow`
/// (spacing 11, 15pt icon column, 13.5/500 label, 10/6 padding, radius 9,
/// 0.78 → 0.92 → white icon tones). The body rides a `SidebarAccordion`
/// so its open/close matches Pinned / Tools / Archived.
struct LifeSidebarSection: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var store = LifeVerticalsStore.shared
    @StateObject private var flags = FeatureFlags.shared

    @AppStorage(ClawixPersistentSurfaceKeys.sidebarLifeExpanded, store: SidebarPrefs.store)
    private var expanded: Bool = true

    /// Estimated nav-row height for the accordion's target. Slightly under
    /// the rendered height so `SidebarAccordion`'s measured height wins and
    /// the open state lands on the content's exact size. Matches the value
    /// the Tools section uses (`ToolsReorderableList.rowSlotHeight`).
    private let rowHeight: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BasicSectionHeader(
                title: "Life",
                expanded: $expanded,
                leadingIcon: AnyView(UserIcon(size: 16)),
                controlId: "sidebar.section.life",
                controlLabel: "Life",
                trailingIcon: AnyView(configureButton)
            )
            SidebarAccordion(
                expanded: expanded,
                targetHeight: CGFloat(visibleVerticals.count + 1) * rowHeight
                    + SidebarRowMetrics.sectionEdgePadding
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    LifeNavRow(
                        title: "All verticals",
                        icon: "circle",
                        selected: isRouteSelected(.lifeHome),
                        onTap: { appState.navigate(to: .lifeHome) }
                    )
                    ForEach(visibleVerticals, id: \.id) { entry in
                        row(for: entry)
                    }
                    Color.clear.frame(height: SidebarRowMetrics.sectionEdgePadding)
                }
                .padding(.leading, 8)
            }
        }
    }

    /// Hover-reveal trailing affordance, mirroring the Pinned funnel /
    /// Tools filter so the whole sidebar shares one header-icon language.
    private var configureButton: some View {
        HeaderHoverIcon(tooltip: "Configure Life verticals") {
            appState.navigate(to: .lifeSettings)
        } label: { color in
            LucideIcon.auto("list.bullet", size: 13)
                .foregroundColor(color)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
    }

    private func row(for entry: LifeRegistryEntry) -> some View {
        let route = SidebarRoute.lifeVertical(id: entry.id)
        return LifeNavRow(
            title: entry.label,
            icon: iconName(for: entry),
            selected: isRouteSelected(route),
            onTap: { appState.navigate(to: route) }
        ) {
            if let label = entry.legalGuardLabel {
                Text(label)
                    .font(BodyFont.system(size: 10, wght: 600))
                    .foregroundColor(Color.orange.opacity(0.78))
                    .help(entry.legalGuardDescription ?? "")
            }
            if entry.status == .devOnly {
                Text("DEV")
                    .font(BodyFont.system(size: 10, wght: 600))
                    .foregroundColor(Color.gray(light: 0.50, dark: 0.45))
            }
        }
    }

    private var visibleVerticals: [LifeRegistryEntry] {
        let ids = store.enabledVerticalIds
        let hidden = store.hiddenVerticalIds
        return ids.compactMap { id in
            guard !hidden.contains(id) else { return nil }
            return LifeRegistry.entry(byId: id, includeDevOnly: flags.developerSurfaces)
        }
    }

    private func isRouteSelected(_ route: SidebarRoute) -> Bool {
        appState.currentRoute == route
    }

    private func iconName(for entry: LifeRegistryEntry) -> String {
        switch entry.iconHint {
        case "heart": return "circle"
        case "moon": return "moon"
        case "dumbbell": return "circle"
        case "smile": return "circle"
        case "book": return "doc.text"
        case "check": return "checkmark.circle"
        case "timer": return "timer"
        case "flag": return "flag"
        case "wallet": return "cylinder.split.1x2"
        case "apple": return "circle"
        case "droplet": return "circle"
        case "scale": return "circle"
        case "screen": return "app"
        case "scissors": return "crop"
        case "cycle": return "clock.arrow.circlepath"
        case "pill": return "circle"
        case "cloud-moon": return "cloud.moon"
        case "spark": return "star"
        case "stars": return "star"
        case "repeat": return "arrow.clockwise"
        case "bolt": return "bolt"
        case "x": return "xmark.circle"
        case "speech": return "bubble.left"
        case "users": return "circle"
        case "pen": return "pencil"
        case "camera": return "camera"
        case "chef": return "circle"
        case "target": return "viewfinder"
        case "book-open": return "doc.text"
        case "music": return "waveform"
        case "gamepad": return "app"
        case "bookmark": return "bookmark"
        case "fork": return "circle"
        case "calendar-event": return "clock"
        case "people": return "circle"
        case "gift": return "archivebox"
        case "swords": return "shield"
        case "link": return "link"
        case "academic": return "doc.text"
        case "hand-coins": return "cylinder.split.1x2"
        case "hands": return "circle"
        case "phone": return "app"
        case "plane": return "arrow.up.right"
        case "location": return "globe"
        case "cloud": return "globe"
        case "leaf": return "circle"
        case "shirt": return "circle"
        case "box": return "archivebox"
        case "credit": return "cylinder.split.1x2"
        case "paw": return "circle"
        case "house": return "folder"
        case "plant": return "circle"
        case "car": return "app"
        case "briefcase": return "folder"
        case "trending-up": return "arrow.up.right"
        case "brain": return "brain"
        case "star": return "star.circle"
        case "trophy": return "badge.check"
        case "lightbulb": return "lightbulb"
        case "puzzle": return "app.dashed"
        case "fingerprint": return "person.crop.circle"
        case "thought": return "bubble.middle.bottom"
        case "compass": return "safari"
        case "flame": return "flame"
        case "handshake": return "circle"
        case "chart": return "arrow.up.right"
        case "split": return "arrow.triangle.branch"
        case "quote": return "quote.bubble"
        case "lotus": return "circle"
        case "graduation": return "doc.text"
        case "calendar-year": return "clock"
        case "heart-hand": return "circle"
        case "stretch": return "circle"
        case "body": return "circle"
        case "heart-private": return "eye.slash"
        case "flask": return "circle"
        case "ruler": return "viewfinder"
        default: return "circle"
        }
    }
}

/// Canonical sidebar nav row for the Life section. Same metrics and tones
/// as `DatabaseToolRow` / `SidebarButton`; an optional trailing slot holds
/// per-vertical badges (legal guard, DEV).
private struct LifeNavRow<Trailing: View>: View {
    let title: String
    let icon: String
    let selected: Bool
    let onTap: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    @State private var hovered = false

    init(
        title: String,
        icon: String,
        selected: Bool,
        onTap: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.icon = icon
        self.selected = selected
        self.onTap = onTap
        self.trailing = trailing
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 11) {
                LucideIcon.auto(icon, size: 12.5)
                    .frame(width: 15, height: 15)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(BodyFont.system(size: 13.5, wght: 500))
                    .foregroundColor(labelColor)
                    .lineLimit(1)
                Spacer(minLength: 6)
                trailing()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(backgroundFill)
            )
            .animation(.easeOut(duration: 0.12), value: hovered)
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var iconColor: Color {
        if selected { return .white }
        return (hovered ? Color.gray(light: 0.14, dark: 0.92) : Color.gray(light: 0.27, dark: 0.78))
    }

    private var labelColor: Color {
        selected ? .white : Color.gray(light: 0.14, dark: 0.92)
    }

    private var backgroundFill: Color {
        if selected { return Color.overlay(0.06) }
        if hovered  { return Color.overlay(0.035) }
        return .clear
    }
}
