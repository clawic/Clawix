import SwiftUI

/// Right-side detail panel for a single skill. Reached from the
/// catalog via `.skillDetail(slug:)`. Sections (top to bottom):
/// header (icon, name, kind/version/author), description, activation
/// toggles per scope, parameter form (only for templates), curated
/// presets, sync target toggles, body markdown viewer/editor,
/// destructive actions (freeze, delete) at the bottom.
struct SkillDetailView: View {
    let slug: String
    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var vault: SecretsManager

    @State private var editingBody = false
    @State private var bodyDraft: String = ""
    @State private var paramDraft: [String: SkillParamValue] = [:]
    @State private var pendingDelete: SkillSpec?

    private var store: SkillsStore? { appState.skillsStore }
    private var skill: SkillSpec? { store?.skill(slug: slug) }

    var body: some View {
        ScrollView {
            if let skill {
                content(for: skill)
            } else {
                missingState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .thinScrollers()
        .onAppear {
            appState.ensureSkillsStoreLoaded()
            hydrateDrafts()
        }
        .onChange(of: slug) { _, _ in hydrateDrafts() }
        .alert(item: $pendingDelete) { skill in
            Alert(
                title: Text("Delete \"\(skill.name)\"?"),
                message: Text("This removes the skill from your local catalog. This cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    store?.remove(slug: skill.slug)
                    appState.navigate(to: .skills)
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private func content(for skill: SkillSpec) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            backLink
            headerBlock(skill)
            descriptionBlock(skill)
            activationBlock(skill)
            if let params = skill.params, !params.isEmpty, !skill.isInstance {
                paramsBlock(skill, params: params)
            }
            if let presets = skill.presets, !presets.isEmpty {
                curatedPresetsBlock(skill, presets: presets)
            }
            if skill.isInstance {
                instanceBlock(skill)
            }
            syncBlock(skill)
            bodyBlock(skill)
            destructiveBlock(skill)
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 60)
        .frame(maxWidth: 880, alignment: .leading)
    }

    private var backLink: some View {
        Button { appState.navigate(to: .skills) } label: {
            HStack(spacing: 5) {
                IconImage("chevron.left", size: 11)
                Text("All skills").font(BodyFont.system(size: 12, wght: 500))
            }
            .foregroundColor(Palette.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private func headerBlock(_ skill: SkillSpec) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconImage(skill.kind.icon, size: 22)
                .foregroundColor(Palette.textSecondary)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(skill.name)
                    .font(BodyFont.system(size: 22, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                HStack(spacing: 6) {
                    Text(skill.kind.label)
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                    Text("v\(skill.version)").font(BodyFont.system(size: 11)).foregroundColor(Palette.textSecondary)
                    if let author = skill.author {
                        Text("·").foregroundColor(Palette.textSecondary)
                        Text("by \(author)").font(BodyFont.system(size: 11)).foregroundColor(Palette.textSecondary)
                    }
                    if skill.builtin {
                        Text("·").foregroundColor(Palette.textSecondary)
                        Text("Built-in").font(BodyFont.system(size: 11)).foregroundColor(Palette.textSecondary)
                    }
                    if let importedFrom = skill.importedFrom {
                        Text("·").foregroundColor(Palette.textSecondary)
                        Text("imported from \(importedFrom)").font(BodyFont.system(size: 11)).foregroundColor(Palette.textSecondary)
                    }
                }
            }
            Spacer(minLength: 8)
        }
    }

    private func descriptionBlock(_ skill: SkillSpec) -> some View {
        Text(skill.description)
            .font(BodyFont.system(size: 14))
            .foregroundColor(Palette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Activation

    private func activationBlock(_ skill: SkillSpec) -> some View {
        sectionCard(title: "Activation", subtitle: "Where this skill is on. Chat overrides project; project overrides global.") {
            VStack(alignment: .leading, spacing: 8) {
                activationToggle(skill: skill, scopeTag: "global", label: "Active globally")
                if let projectId = currentProjectId, let projectName = currentProjectName {
                    activationToggle(skill: skill, scopeTag: "project:\(projectId)", label: "Active in project: \(projectName)")
                }
                if let chatId = currentChatId {
                    activationToggle(skill: skill, scopeTag: "chat:\(chatId.uuidString)", label: "Active in this chat only")
                }
            }
        }
    }

    private func activationToggle(skill: SkillSpec, scopeTag: String, label: String) -> some View {
        let isOn = store?.isActive(slug: skill.slug, atScope: scopeTag) ?? false
        return HStack(spacing: 12) {
            Text(label)
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textPrimary)
            Spacer(minLength: 12)
            PillToggle(isOn: Binding(
                get: { isOn },
                set: { newValue in
                    store?.setActive(slug: skill.slug, scopeTag: scopeTag, active: newValue, params: paramDraft.isEmpty ? nil : paramDraft)
                }
            ))
        }
    }

    // MARK: - Params (templates)

    private func paramsBlock(_ skill: SkillSpec, params: [SkillParam]) -> some View {
        sectionCard(
            title: "Parameters",
            subtitle: "Configure once, save as your own. The body uses {{key}} placeholders the daemon substitutes at compile-time."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(params) { param in
                    paramRow(param)
                }
                HStack(spacing: 10) {
                    Spacer()
                    Button {
                        store?.instantiate(template: skill, params: paramDraft, frozen: false)
                    } label: {
                        Text("Save as my skill")
                            .font(BodyFont.system(size: 12, wght: 600))
                            .foregroundColor(Color.black)
                            .padding(.horizontal, 14).frame(height: 28)
                            .background(Capsule(style: .continuous).fill(Color.white.opacity(0.92)))
                    }
                    .buttonStyle(.plain)
                    Button {
                        // Use once: just toggle global active with these params,
                        // without persisting an instance.
                        store?.setActive(slug: skill.slug, scopeTag: "global", active: true, params: paramDraft)
                    } label: {
                        Text("Use once")
                            .font(BodyFont.system(size: 12, wght: 500))
                            .foregroundColor(Palette.textPrimary)
                            .padding(.horizontal, 14).frame(height: 28)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.10))
                                    .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func paramRow(_ param: SkillParam) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(param.label)
                    .font(BodyFont.system(size: 11, wght: 600))
                    .foregroundColor(Palette.textSecondary)
                if param.required {
                    Text("required")
                        .font(BodyFont.system(size: 9.5, wght: 600))
                        .foregroundColor(Palette.textSecondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                }
            }
            paramControl(param)
            if let prompt = param.prompt {
                Text(prompt).font(BodyFont.system(size: 10.5)).foregroundColor(Palette.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func paramControl(_ param: SkillParam) -> some View {
        switch param.type {
        case .enumValue:
            let options = param.options ?? []
            SettingsDropdown(
                options: options.map { ($0, $0) },
                selection: Binding(
                    get: { (paramDraft[param.key] ?? param.defaultValue ?? .string("")).displayString },
                    set: { newValue in paramDraft[param.key] = .string(newValue) }
                )
            )
            .frame(maxWidth: 240, alignment: .leading)
        case .string:
            TextField("", text: Binding(
                get: { (paramDraft[param.key] ?? param.defaultValue ?? .string("")).displayString },
                set: { newValue in paramDraft[param.key] = .string(newValue) }
            ))
            .textFieldStyle(.plain)
            .font(BodyFont.system(size: 12))
            .foregroundColor(Palette.textPrimary)
            .modifier(DetailFieldChrome())
            .frame(maxWidth: 360)
        case .number:
            TextField("", value: Binding(
                get: {
                    if case .number(let n) = paramDraft[param.key] { return n }
                    if case .number(let n) = param.defaultValue { return n }
                    return Double(0)
                },
                set: { newValue in paramDraft[param.key] = .number(newValue) }
            ), formatter: NumberFormatter())
            .textFieldStyle(.plain)
            .font(BodyFont.system(size: 12))
            .foregroundColor(Palette.textPrimary)
            .modifier(DetailFieldChrome())
            .frame(maxWidth: 160)
        case .bool:
            PillToggle(isOn: Binding(
                get: {
                    if case .bool(let b) = paramDraft[param.key] { return b }
                    if case .bool(let b) = param.defaultValue { return b }
                    return false
                },
                set: { newValue in paramDraft[param.key] = .bool(newValue) }
            ))
        case .secretRef:
            secretReferenceField(param)
        }
    }

    @ViewBuilder
    private func secretReferenceField(_ param: SkillParam) -> some View {
        if vault.state != .unlocked {
            HStack(spacing: 8) {
                Text("Unlock Secrets to choose a secret.")
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                Button {
                    appState.navigate(to: .secretsHome)
                } label: {
                    Text("Open Secrets")
                        .font(BodyFont.system(size: 11, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                        .padding(.horizontal, 12).frame(height: 26)
                        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }
        } else if vault.secrets.isEmpty {
            Text("No secrets available.")
                .font(BodyFont.system(size: 11))
                .foregroundColor(Palette.textSecondary)
        } else {
            SettingsDropdown(
                options: [("", "Choose a secret")] + vault.secrets.map { secret in
                    (secret.internalName, secret.title.isEmpty ? secret.internalName : "\(secret.title) · \(secret.internalName)")
                },
                selection: Binding(
                    get: {
                        if case .secretRef(let id) = paramDraft[param.key] { return id }
                        if case .secretRef(let id) = param.defaultValue { return id }
                        return ""
                    },
                    set: { newValue in
                        if newValue.isEmpty {
                            paramDraft.removeValue(forKey: param.key)
                        } else {
                            paramDraft[param.key] = .secretRef(id: newValue)
                        }
                    }
                )
            )
            .frame(maxWidth: 360, alignment: .leading)
        }
    }

    // MARK: - Curated presets (template children)

    private func curatedPresetsBlock(_ skill: SkillSpec, presets: [SkillPreset]) -> some View {
        sectionCard(title: "Curated presets", subtitle: "Quick configurations the author bundled. Picking one creates an instance you can fine-tune.") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(presets) { preset in
                    Button {
                        store?.instantiate(template: skill, params: preset.params, saveAs: preset.slug, frozen: false)
                    } label: {
                        HStack {
                            IconImage("sparkles", size: 11)
                                .foregroundColor(Palette.textSecondary)
                            Text(preset.label)
                                .font(BodyFont.system(size: 12.5, wght: 500))
                                .foregroundColor(Palette.textPrimary)
                            Spacer(minLength: 8)
                            Text("Save as instance")
                                .font(BodyFont.system(size: 11)).foregroundColor(Palette.pastelBlue)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Instance block (when this is an instance, not a template)

    private func instanceBlock(_ skill: SkillSpec) -> some View {
        guard let ref = skill.instance else { return AnyView(EmptyView()) }
        let template = store?.skill(slug: ref.ofTemplate)
        return AnyView(sectionCard(title: ref.frozen ? "Frozen snapshot" : "Instance of template", subtitle: ref.frozen
            ? "Body has been rendered once and the link to the template was dropped. Future template updates won't propagate."
            : "Body is rendered live from the template. Click Freeze to lock in the current copy.") {
            VStack(alignment: .leading, spacing: 8) {
                if let template {
                    HStack(spacing: 6) {
                        IconImage("link", size: 11).foregroundColor(Palette.textSecondary)
                        Text("Template:").font(BodyFont.system(size: 11)).foregroundColor(Palette.textSecondary)
                        Button { appState.navigate(to: .skillDetail(slug: template.slug)) } label: {
                            Text(template.name).font(BodyFont.system(size: 12, wght: 500)).foregroundColor(Palette.pastelBlue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !ref.params.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Params").font(BodyFont.system(size: 11, wght: 600)).foregroundColor(Palette.textSecondary)
                        ForEach(ref.params.keys.sorted(), id: \.self) { key in
                            HStack(spacing: 6) {
                                Text(key).font(BodyFont.system(size: 11, wght: 500)).foregroundColor(Palette.textPrimary)
                                Text("=").foregroundColor(Palette.textSecondary)
                                Text(ref.params[key]?.displayString ?? "")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(Palette.textPrimary)
                            }
                        }
                    }
                }
                if !ref.frozen {
                    HStack {
                        Spacer()
                        Button {
                            store?.freeze(instanceSlug: skill.slug)
                        } label: {
                            Text("Freeze")
                                .font(BodyFont.system(size: 12, wght: 600))
                                .foregroundColor(Color.black)
                                .padding(.horizontal, 14).frame(height: 28)
                                .background(Capsule(style: .continuous).fill(Color.white.opacity(0.92)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        })
    }

    // MARK: - Sync targets

    private func syncBlock(_ skill: SkillSpec) -> some View {
        sectionCard(title: "Sync to other agents", subtitle: "Materialise this skill in other agents' home dirs (\(ClawixSkillsRoutes.defaultExternalDirectoriesSummary)) via symlinks. They consume it as a normal SKILL.md.") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(store?.syncTargets ?? []) { target in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(target.label).font(BodyFont.system(size: 12.5, wght: 500)).foregroundColor(Palette.textPrimary)
                            Text(target.home)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(Palette.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        PillToggle(isOn: Binding(
                            get: { skill.syncTo.contains(target.id) },
                            set: { newValue in store?.setSyncTarget(slug: skill.slug, target: target.id, enabled: newValue) }
                        ))
                    }
                    .padding(.vertical, 2)
                }
                if (store?.syncTargets.isEmpty ?? true) {
                    Text("No sync targets configured. Add them in Settings → Skills.")
                        .font(BodyFont.system(size: 11)).foregroundColor(Palette.textSecondary)
                }
            }
        }
    }

    // MARK: - Body editor

    private func bodyBlock(_ skill: SkillSpec) -> some View {
        sectionCard(title: "Body (markdown)", subtitle: editingBody ? "Editing. Save to persist." : "What the model sees in its system prompt when this skill is active.", trailing: editButton(skill: skill)) {
            if editingBody {
                TextEditor(text: $bodyDraft)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Palette.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 240)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                    )
            } else {
                Text(skill.body)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    private func editButton(skill: SkillSpec) -> AnyView {
        if skill.builtin {
            return AnyView(
                Text("Built-in (clone to edit)")
                    .font(BodyFont.system(size: 11)).foregroundColor(Palette.textSecondary)
            )
        }
        if editingBody {
            return AnyView(
                HStack(spacing: 6) {
                    Button("Cancel") {
                        editingBody = false
                        bodyDraft = skill.body
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Palette.textSecondary)
                    .font(BodyFont.system(size: 11, wght: 500))
                    Button {
                        var copy = skill
                        copy.body = bodyDraft
                        copy.updatedAt = ISO8601DateFormatter().string(from: Date())
                        store?.upsert(copy)
                        editingBody = false
                    } label: {
                        Text("Save")
                            .font(BodyFont.system(size: 11, wght: 600))
                            .foregroundColor(Color.black)
                            .padding(.horizontal, 12).frame(height: 24)
                            .background(Capsule(style: .continuous).fill(Color.white.opacity(0.92)))
                    }
                    .buttonStyle(.plain)
                }
            )
        }
        return AnyView(
            Button { editingBody = true } label: {
                Text("Edit").font(BodyFont.system(size: 11, wght: 600)).foregroundColor(Palette.pastelBlue)
            }
            .buttonStyle(.plain)
        )
    }

    // MARK: - Destructive

    private func destructiveBlock(_ skill: SkillSpec) -> some View {
        guard !skill.builtin else { return AnyView(EmptyView()) }
        return AnyView(
            HStack {
                Spacer()
                Button {
                    pendingDelete = skill
                } label: {
                    Text("Delete skill")
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(Color.red.opacity(0.9))
                        .padding(.horizontal, 14).frame(height: 28)
                        .background(
                            Capsule(style: .continuous)
                                .stroke(Color.red.opacity(0.4), lineWidth: 0.7)
                        )
                }
                .buttonStyle(.plain)
            }
        )
    }

    // MARK: - Empty state

    private var missingState: some View {
        VStack(spacing: 14) {
            IconImage("questionmark.circle", size: 34)
                .foregroundColor(Palette.textSecondary)
            Text("Skill not found.")
                .font(BodyFont.system(size: 15, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
            Button { appState.navigate(to: .skills) } label: {
                Text("Back to all skills")
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 14).frame(height: 28)
                    .background(Capsule(style: .continuous).fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Helpers

    private var currentChatId: UUID? {
        if case let .chat(id) = appState.currentRoute { return id }
        return nil
    }

    private var currentProjectId: String? {
        if let chatId = currentChatId,
           let chat = appState.chats.first(where: { $0.id == chatId }),
           let pid = chat.projectId {
            return pid.uuidString
        }
        if let project = appState.selectedProject {
            return project.id.uuidString
        }
        return nil
    }

    private var currentProjectName: String? {
        guard let projectId = currentProjectId,
              let uuid = UUID(uuidString: projectId),
              let project = appState.projects.first(where: { $0.id == uuid }) else { return nil }
        return project.name
    }

    private func hydrateDrafts() {
        guard let skill else { return }
        bodyDraft = skill.body
        // Populate paramDraft from skill defaults or instance params.
        var draft: [String: SkillParamValue] = [:]
        if let instance = skill.instance {
            draft = instance.params
        } else if let params = skill.params {
            for param in params {
                if let def = param.defaultValue { draft[param.key] = def }
            }
        }
        paramDraft = draft
    }

    // MARK: - Section card chrome

    @ViewBuilder
    private func sectionCard<Content: View>(
        title: String,
        subtitle: String? = nil,
        trailing: AnyView? = nil,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(BodyFont.system(size: 12.5, weight: .semibold)).foregroundColor(Palette.textPrimary)
                Spacer(minLength: 4)
                if let trailing { trailing }
            }
            if let subtitle {
                Text(subtitle).font(BodyFont.system(size: 11)).foregroundColor(Palette.textSecondary)
            }
            content()
                .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.085))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }
}

/// Canon single-line input chrome for detail-panel text fields: soft
/// dark fill, hairline stroke, squircle corners (STYLE section 6.8).
private struct DetailFieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            )
    }
}
