import SwiftUI

/// Top-level page reachable from the sidebar (⌘⇧K). Renders the user's
/// central library: built-ins + user-created + auto-imported from
/// external agent dirs. Filters by kind/scope/tag, free-text search,
/// "+ New skill" button, and a Sync now action.
///
/// Layout: header bar → filter strip → grid of skill cards. Click a
/// card to open `SkillDetailView` in the same content column.
struct SkillsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var localStore: SkillsStore = SkillsStore(loadMode: .none)

    private var store: SkillsStore { appState.skillsStore ?? localStore }

    @State private var creatingNew = false
    @State private var searchQuery = ""
    @FocusState private var searchFocused: Bool
    @State private var kindFilter: SkillKind? = nil
    @State private var scopeFilter: SkillScopeKind? = nil
    @State private var tagFilter: String? = nil
    @State private var storeRefreshToken = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                filterStrip
                if filteredSkills.isEmpty {
                    emptyState
                        .padding(.top, 60)
                } else {
                    grid
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .thinScrollers()
        .sheet(isPresented: $creatingNew) {
            SkillNewSheet(store: store, onClose: {
                creatingNew = false
                storeRefreshToken &+= 1
            })
        }
        .onReceive(store.objectWillChange) { _ in
            storeRefreshToken &+= 1
        }
        .onAppear {
            guard FeatureFlags.shared.isVisible(.skills) else { return }
            appState.ensureSkillsStoreLoaded()
            storeRefreshToken &+= 1
        }
        .onDisappear {
            store.cancelSurfaceWork()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Skills")
                    .font(BodyFont.system(size: 22, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Text("Your central library. Activate per chat, project or globally. Sync to other agents on toggle.")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer(minLength: 12)
            searchField
                .frame(maxWidth: 280)
            syncButton
            IconChipButton(symbol: "plus", label: "New skill", isPrimary: true) {
                creatingNew = true
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            IconImage("magnifyingglass", size: 12)
                .foregroundColor(Palette.textSecondary)
            TextField("Search skills…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textPrimary)
                .focused($searchFocused)
            if !searchQuery.isEmpty {
                IconCircleButton(symbol: "xmark", size: 18, symbolSize: 9) {
                    searchQuery = ""
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(
            Capsule(style: .continuous)
                .fill(Color.overlay(searchFocused ? 0.08 : 0.06))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(searchFocused ? Palette.pastelBlue.opacity(0.6) : .clear, lineWidth: 1)
                )
        )
    }

    private var syncButton: some View {
        Group {
            if store.pendingOperation != nil {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Syncing…")
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(Palette.textPrimary)
                }
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.gray(light: 0.94, dark: 0.135))
                        .overlay(Capsule(style: .continuous).stroke(Color.overlay(0.10), lineWidth: 0.5))
                )
                .help(syncHelpText)
            } else {
                IconChipButton(symbol: "arrow.triangle.2.circlepath", label: "Sync now") {
                    Task { await store.syncNow() }
                }
                .help(syncHelpText)
            }
        }
    }

    private var syncHelpText: String {
        if let date = store.lastSyncedAt {
            let formatter = RelativeDateTimeFormatter()
            return "Last synced \(formatter.localizedString(for: date, relativeTo: Date()))"
        } else {
            return "Sync skills to \(ClawixSkillsRoutes.defaultExternalDirectoriesSummary)"
        }
    }

    // MARK: - Filter strip

    private var filterStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                FilterChip(label: "All kinds", active: kindFilter == nil) { kindFilter = nil }
                ForEach(SkillKind.allCases) { kind in
                    FilterChip(label: kind.label, active: kindFilter == kind) { kindFilter = kind }
                }
                Spacer(minLength: 12)
                resetFiltersButton
            }
            tagCloud
        }
    }

    private var resetFiltersButton: some View {
        Button {
            kindFilter = nil
            scopeFilter = nil
            tagFilter = nil
            searchQuery = ""
        } label: {
            Text("Reset filters")
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(Palette.textSecondary)
        }
        .buttonStyle(.plain)
        .opacity(hasAnyFilter ? 1 : 0)
    }

    private var hasAnyFilter: Bool {
        kindFilter != nil || scopeFilter != nil || tagFilter != nil || !searchQuery.isEmpty
    }

    private var tagCloud: some View {
        let tags = store.allTags()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags.prefix(40), id: \.self) { tag in
                    FilterChip(label: "#\(tag)", active: tagFilter == tag) {
                        tagFilter = (tagFilter == tag) ? nil : tag
                    }
                }
            }
        }
    }

    // MARK: - Grid

    private var filteredSkills: [SkillSpec] {
        _ = storeRefreshToken
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.catalog.filter { skill in
            if let kindFilter, skill.kind != kindFilter { return false }
            if let scopeFilter, skill.scope.kind != scopeFilter { return false }
            if let tagFilter, !skill.tags.contains(tagFilter) { return false }
            guard !q.isEmpty else { return true }
            if skill.name.lowercased().contains(q) { return true }
            if skill.description.lowercased().contains(q) { return true }
            if skill.tags.contains(where: { $0.lowercased().contains(q) }) { return true }
            if skill.body.lowercased().contains(q) { return true }
            return false
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var grid: some View {
        let columns = [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 14)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(filteredSkills) { skill in
                SkillCardView(skill: skill, store: store) {
                    appState.navigate(to: .skillDetail(slug: skill.slug))
                }
            }
        }
        .id(storeRefreshToken)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            IconImage("wand.and.stars", size: 36)
                .foregroundColor(Palette.textSecondary)
            Text(hasAnyFilter ? "No skills match these filters." : "No skills yet.")
                .font(BodyFont.system(size: 15, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
            Text(hasAnyFilter
                 ? "Try clearing some filters above, or create a new skill."
                 : "Create your first skill, or wait for the auto-importer to pull from \(ClawixSkillsRoutes.defaultExternalDirectoriesSummary).")
                .font(BodyFont.system(size: 12))
                .foregroundColor(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            IconChipButton(symbol: "plus", label: "New skill", isPrimary: true) {
                creatingNew = true
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Skill card

private struct SkillCardView: View {
    let skill: SkillSpec
    @ObservedObject var store: SkillsStore
    let onTap: () -> Void

    @State private var hovered = false

    private var globalActive: Bool {
        store.isActive(slug: skill.slug, atScope: "global")
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    IconImage(skill.kind.icon, size: 13)
                        .foregroundColor(Palette.textSecondary)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.overlay(0.06))
                        )
                    Text(skill.name)
                        .font(BodyFont.system(size: 13.5, weight: .semibold))
                        .foregroundColor(Palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if globalActive {
                        Text("Active")
                            .font(BodyFont.system(size: 10, wght: 600))
                            .foregroundColor(Palette.pastelBlue)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Palette.pastelBlue.opacity(0.16))
                            )
                    }
                }
                Text(skill.description)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    metaPill(skill.kind.label)
                    if skill.builtin {
                        metaPill("Built-in")
                    }
                    if let importedFrom = skill.importedFrom {
                        metaPill("via \(importedFrom)")
                    }
                    if skill.isInstance {
                        metaPill("instance")
                    }
                    Spacer(minLength: 4)
                    if !skill.syncTo.isEmpty {
                        IconImage("arrow.triangle.2.circlepath", size: 10)
                            .foregroundColor(Palette.textSecondary)
                        Text("\(skill.syncTo.count)")
                            .font(BodyFont.system(size: 10, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hovered ? Palette.cardHover : Palette.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(hovered ? Palette.border : Palette.popupStroke, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private func metaPill(_ text: String) -> some View {
        Text(text)
            .font(BodyFont.system(size: 10, wght: 500))
            .foregroundColor(Palette.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.overlay(0.06)))
    }
}

// MARK: - New skill sheet

private struct SkillNewSheet: View {
    @ObservedObject var store: SkillsStore
    let onClose: () -> Void

    @State private var slug: String = ""
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var kind: SkillKind = .procedure
    @State private var skillBody: String = ""

    var canSubmit: Bool {
        !slug.trimmingCharacters(in: .whitespaces).isEmpty &&
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("New skill")
                    .font(BodyFont.system(size: 18, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                IconCircleButton(symbol: "xmark") { onClose() }
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Kind")
                SlidingSegmented(
                    selection: $kind,
                    options: SkillKind.allCases.map { ($0, $0.label) }
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Slug")
                TextField("e.g. my-cold-email", text: $slug)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Palette.textPrimary)
                    .modifier(SheetFieldChrome())
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Name")
                TextField("Display name shown in the catalog", text: $name)
                    .textFieldStyle(.plain)
                    .font(BodyFont.system(size: 13))
                    .foregroundColor(Palette.textPrimary)
                    .modifier(SheetFieldChrome())
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Description")
                TextField("One-liner shown on the card", text: $description)
                    .textFieldStyle(.plain)
                    .font(BodyFont.system(size: 13))
                    .foregroundColor(Palette.textPrimary)
                    .modifier(SheetFieldChrome())
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Body (markdown)")
                TextEditor(text: $skillBody)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Palette.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 160)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.overlay(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.overlay(0.10), lineWidth: 0.5)
                            )
                    )
            }

            HStack {
                Spacer()
                Button {
                    submit()
                } label: {
                    Text("Create")
                        .font(BodyFont.system(size: 13, wght: 600))
                        // Capsule fill is `Color.overlay(0.92)` (white on dark,
                        // black on light); the label uses `Palette.background`
                        // (the app-wide CTA idiom) so it inverts with the fill
                        // instead of staying black-on-black in light mode.
                        .foregroundColor(canSubmit ? Palette.background : Color.overlay(0.55))
                        .padding(.horizontal, 18)
                        .frame(height: 30)
                        .background(
                            Capsule(style: .continuous)
                                .fill(canSubmit ? Color.overlay(0.92) : Color.overlay(0.18))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(Palette.background)
    }

    private func fieldLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(BodyFont.system(size: 11, wght: 600))
            .foregroundColor(Palette.textSecondary)
    }

    private func submit() {
        guard canSubmit else { return }
        let skill = SkillSpec(
            slug: slug.trimmingCharacters(in: .whitespacesAndNewlines),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            version: "0.1.0",
            kind: kind,
            body: skillBody,
            scope: .global,
            tags: [],
            syncTo: [],
            syncMode: .symlink,
            params: nil,
            instance: nil,
            capsule: nil,
            soul: nil,
            presets: nil,
            builtin: false,
            importedFrom: nil,
            author: "you",
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        store.upsert(skill)
        onClose()
    }
}

/// Canonical single-line input chrome for sheet text fields: soft dark
/// fill, hairline stroke, squircle corners (section 6.8).
private struct SheetFieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.overlay(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.overlay(0.10), lineWidth: 0.5)
                    )
            )
    }
}
