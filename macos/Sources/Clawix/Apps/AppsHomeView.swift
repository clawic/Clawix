import AppKit
import SwiftUI

/// "All apps" landing screen the user reaches from the sidebar Apps
/// section header. Renders the catalog as a grid with filters by
/// project + tag and an inline search box. Each card opens the app
/// in the center pane on click.
struct AppsHomeView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var appsStore: AppsStore = .shared

    @State private var query: String = ""
    @State private var selectedProjectId: UUID? = nil
    @State private var selectedTag: String = ""
    @State private var sortMode: AppsSortMode = .recent
    @State private var pendingDelete: AppRecord?

    enum AppsSortMode: String, CaseIterable, Identifiable {
        case recent
        case name
        case created

        var id: String { rawValue }

        var label: String {
            switch self {
            case .recent:  return "Recently used"
            case .name:    return "Name"
            case .created: return "Date created"
            }
        }
    }

    private var allTags: [String] {
        let bag = Set(appsStore.apps.flatMap(\.tags))
        return bag.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var filteredApps: [AppRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = appsStore.apps.filter { record in
            if let pid = selectedProjectId, record.projectId != pid { return false }
            if !selectedTag.isEmpty, !record.tags.contains(selectedTag) { return false }
            if !trimmed.isEmpty {
                let haystack = "\(record.name) \(record.description) \(record.tags.joined(separator: " "))".lowercased()
                if !haystack.contains(trimmed) { return false }
            }
            return true
        }
        switch sortMode {
        case .recent:
            return base.sorted(by: { (lhs, rhs) in
                if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
                let l = lhs.lastOpenedAt ?? .distantPast
                let r = rhs.lastOpenedAt ?? .distantPast
                if l != r { return l > r }
                return lhs.createdAt > rhs.createdAt
            })
        case .name:
            return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .created:
            return base.sorted { $0.createdAt > $1.createdAt }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            filterBar
                .padding(.horizontal, 32)
                .padding(.bottom, 18)
            Rectangle()
                .fill(Palette.popupStroke)
                .frame(height: 0.5)
            ScrollView {
                if filteredApps.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 18, alignment: .top)
                    ], spacing: 18) {
                        ForEach(filteredApps) { record in
                            AppCard(record: record) {
                                appState.navigate(to: .app(record.id))
                            } onDelete: {
                                pendingDelete = record
                            }
                        }
                    }
                    .padding(32)
                }
            }
            .thinScrollers()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.background)
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

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Apps")
                    .font(BodyFont.system(size: 26, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text("Mini apps your agent has built")
                    .font(BodyFont.system(size: 13.5, wght: 400))
                    .foregroundColor(Color.gray(light: 0.40, dark: 0.62))
            }
            Spacer()
            Button {
                importPackage()
            } label: {
                IconImage("square.and.arrow.down", size: 12)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Import app package")
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.gray(light: 0.95, dark: 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.overlay(0.10), lineWidth: 0.7)
            )
            .foregroundColor(Color.gray(light: 0.19, dark: 0.86))
            HStack(spacing: 8) {
                IconImage("magnifyingglass", size: 12)
                    .foregroundColor(Color.gray(light: 0.45, dark: 0.55))
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .foregroundColor(Color.gray(light: 0.14, dark: 0.92))
                    .frame(width: 200)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.gray(light: 0.95, dark: 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.overlay(0.10), lineWidth: 0.7)
            )
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 16)
    }

    private func importPackage() {
        let panel = NSOpenPanel()
        panel.title = "Import App Package"
        panel.message = "Choose a folder containing a Clawix manifest.json package."
        panel.prompt = "Import"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = AppsStore.defaultRootURL().deletingLastPathComponent()

        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
        do {
            let imported = try appsStore.importApp(from: sourceURL, originClass: .imported)
            ToastCenter.shared.show("Imported \(imported.name)")
            appState.navigate(to: .app(imported.id))
        } catch {
            ToastCenter.shared.show(error.localizedDescription, icon: .error)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            sortMenu
            projectMenu
            tagMenu
            Spacer()
            Text("\(filteredApps.count) of \(appsStore.apps.count)")
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(Color.gray(light: 0.45, dark: 0.55))
        }
    }

    private var sortMenu: some View {
        AppsFilterDropdown(
            chipText: "Sort: \(sortMode.label)",
            options: AppsSortMode.allCases.map { mode in
                AppsFilterOption(title: mode.label, isSelected: mode == sortMode) { sortMode = mode }
            }
        )
    }

    private var projectMenu: some View {
        let label = selectedProjectId.flatMap { pid in
            appState.projects.first(where: { $0.id == pid })?.name
        } ?? "All projects"
        var options = [AppsFilterOption(title: "All projects", isSelected: selectedProjectId == nil) { selectedProjectId = nil }]
        options += appState.projects.map { project in
            AppsFilterOption(title: project.name, isSelected: selectedProjectId == project.id) { selectedProjectId = project.id }
        }
        return AppsFilterDropdown(chipText: "Project: \(label)", options: options)
    }

    private var tagMenu: some View {
        var options = [AppsFilterOption(title: "All tags", isSelected: selectedTag.isEmpty) { selectedTag = "" }]
        options += allTags.map { tag in
            AppsFilterOption(title: tag, isSelected: selectedTag == tag) { selectedTag = tag }
        }
        return AppsFilterDropdown(chipText: selectedTag.isEmpty ? "Tag: All" : "Tag: \(selectedTag)", options: options)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            IconImage("app.dashed", size: 30)
                .foregroundColor(Color.gray(light: 0.50, dark: 0.45))
            Text(appsStore.apps.isEmpty
                 ? "No apps yet"
                 : "No apps match your filters")
                .font(BodyFont.system(size: 15, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Text(appsStore.apps.isEmpty
                 ? "Ask the agent: \"Build me a mini app that…\""
                 : "Try clearing the search or filter.")
                .font(BodyFont.system(size: 13, wght: 400))
                .foregroundColor(Color.gray(light: 0.42, dark: 0.6))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
    }
}

private struct AppsFilterOption: Identifiable {
    let id = UUID()
    let title: String
    let isSelected: Bool
    let action: () -> Void
}

/// Filter dropdown for the Apps catalog header. Replaces the system
/// `Menu` (which renders un-themed macOS popups) with the canon dropdown
/// chrome: anchored popup, `menuStandardBackground`, `MenuRowHover`,
/// `softNudge` transition. (STYLE 6.3.)
private struct AppsFilterDropdown: View {
    let chipText: String
    let options: [AppsFilterOption]

    @State private var isOpen = false
    @State private var hoveredIndex: Int? = nil

    var body: some View {
        Button { isOpen.toggle() } label: {
            FilterChipLabel(text: chipText)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .anchorPreference(key: AppsFilterAnchorKey.self, value: .bounds) { $0 }
        .overlayPreferenceValue(AppsFilterAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if isOpen, let anchor {
                    popup
                        .anchoredPopupPlacement(
                            buttonFrame: proxy[anchor],
                            proxy: proxy,
                            horizontal: .leading()
                        )
                        .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(isOpen)
        }
        .animation(MenuStyle.openAnimation, value: isOpen)
    }

    private var popup: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                Button {
                    opt.action()
                    isOpen = false
                } label: {
                    HStack(spacing: 10) {
                        Text(opt.title)
                            .font(BodyFont.system(size: 12.5))
                            .foregroundColor(MenuStyle.rowText)
                            .lineLimit(1)
                        Spacer(minLength: 16)
                        if opt.isSelected {
                            CheckIcon(size: 11)
                                .foregroundColor(MenuStyle.rowText)
                        }
                    }
                    .padding(.horizontal, MenuStyle.rowHorizontalPadding)
                    .padding(.vertical, MenuStyle.rowVerticalPadding)
                    .background(MenuRowHover(active: hoveredIndex == idx))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { hoveredIndex = idx }
                    else if hoveredIndex == idx { hoveredIndex = nil }
                }
            }
        }
        .frame(minWidth: 170, alignment: .leading)
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isOpen))
    }
}

private struct AppsFilterAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

private struct FilterChipLabel: View {
    let text: String
    var body: some View {
        HStack(spacing: 5) {
            Text(text)
                .font(BodyFont.system(size: 12.5, wght: 500))
            LucideIcon(.chevronDown, size: 9)
        }
        .foregroundColor(Color.gray(light: 0.20, dark: 0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.gray(light: 0.95, dark: 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.overlay(0.10), lineWidth: 0.7)
        )
    }
}

private struct AppCard: View {
    let record: AppRecord
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var hovered: Bool = false
    @ObservedObject private var appsStore: AppsStore = .shared

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    iconTile
                        .frame(maxWidth: .infinity, minHeight: 110, maxHeight: 110)
                    if record.pinned {
                        IconImage("pin.fill", size: 11)
                            .foregroundColor(Color.overlay(0.85))
                            .padding(8)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.name)
                        .font(BodyFont.system(size: 14, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                        .lineLimit(1)
                    if !record.description.isEmpty {
                        Text(record.description)
                            .font(BodyFont.system(size: 12.5, wght: 400))
                            .foregroundColor(Color.gray(light: 0.42, dark: 0.6))
                            .lineLimit(2)
                    }
                    if !record.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(record.tags.prefix(3), id: \.self) { tag in
                                Text(tag)
                                    .font(BodyFont.system(size: 10.5, wght: 500))
                                    .foregroundColor(Color.gray(light: 0.33, dark: 0.7))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(Color.overlay(0.06))
                                    )
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(12)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.gray(light: 0.95, dark: 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.overlay(hovered ? 0.20 : 0.08), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .contextMenu {
            Button(record.pinned ? "Unpin from sidebar" : "Pin to sidebar") {
                appsStore.togglePinned(record)
            }
            Divider()
            Button("Delete app", role: .destructive, action: onDelete)
        }
    }

    @ViewBuilder
    private var iconTile: some View {
        let bg = AppCard.tileColor(record: record)
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(
                    colors: [bg.opacity(0.92), bg.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                ))
            if !record.icon.isEmpty {
                Text(record.icon)
                    .font(.system(size: 36))
            } else {
                Text(initials(for: record.name))
                    .font(BodyFont.system(size: 26, wght: 700))
                    .foregroundColor(Color.overlay(0.92))
            }
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 12,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 12,
                style: .continuous
            )
        )
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ", maxSplits: 1)
        if parts.count == 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    static func tileColor(record: AppRecord) -> Color {
        if let parsed = Color(appsHex: record.accentColor) {
            return parsed
        }
        // Deterministic color from slug so the catalog has visual variety.
        var hash: UInt64 = 0
        for byte in record.slug.utf8 { hash = hash &* 131 &+ UInt64(byte) }
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.55)
    }
}
