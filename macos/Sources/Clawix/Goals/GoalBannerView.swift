import SwiftUI

// MARK: - Goal banner
//
// Persistent strip shown above the composer while a chat has a goal. Tapping
// the body edits the goal; trailing controls pause/resume and remove it. A
// thin progress line along the bottom reflects token-budget consumption. When
// the goal is achieved the strip flips to a calm "achieved" summary.

struct GoalBannerView: View {
    let chatId: UUID
    @ObservedObject private var store = GoalStore.shared
    @State private var editing = false

    private var goal: ActiveGoal? { store.goal(for: chatId) }

    private var creationBinding: Binding<Bool> {
        Binding(
            get: { store.creationRequestChatId == chatId },
            set: { if !$0 { store.creationRequestChatId = nil } }
        )
    }

    var body: some View {
        Group {
            if let goal {
                content(goal)
            } else {
                // Zero-height host so the create sheet can attach even when
                // no goal is shown yet.
                Color.clear.frame(height: 0)
            }
        }
        .sheet(isPresented: $editing) {
            if let goal {
                GoalEditSheet(chatId: chatId, existing: goal) { editing = false }
            }
        }
        .sheet(isPresented: creationBinding) {
            GoalEditSheet(chatId: chatId, existing: nil) { store.creationRequestChatId = nil }
        }
    }

    @ViewBuilder
    private func content(_ goal: ActiveGoal) -> some View {
        let status = goal.effectiveStatus
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                statusGlyph(status)

                VStack(alignment: .leading, spacing: 1) {
                    Text(statusLabel(goal, status))
                        .font(BodyFont.system(size: 10.5, wght: 600))
                        .foregroundColor(accent(status))
                    Text(goal.objective)
                        .font(BodyFont.system(size: 12.5, wght: 500))
                        .foregroundColor(Palette.textPrimary.opacity(status == .paused ? 0.6 : 0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                if let budget = goal.tokenBudget, budget > 0 {
                    Text("\(short(goal.tokensUsed)) / \(short(budget))")
                        .font(BodyFont.system(size: 11, design: .monospaced))
                        .foregroundColor(Palette.textSecondary)
                        .monospacedDigit()
                }

                if status != .achieved {
                    bannerButton(goal.status == .paused ? .play : .pause,
                                 label: goal.status == .paused ? L10n.t("Resume goal") : L10n.t("Pause goal")) {
                        store.togglePause(for: chatId)
                    }
                    bannerButton(.check, label: L10n.t("Mark goal achieved")) {
                        withAnimation(.easeOut(duration: 0.18)) { store.markAchieved(for: chatId) }
                    }
                }
                bannerButton(.trash, label: L10n.t("Remove goal"), destructive: true) {
                    withAnimation(.easeOut(duration: 0.18)) { store.remove(for: chatId) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .onTapGesture { if status != .achieved { editing = true } }

            // Budget progress hairline along the bottom edge.
            if let fraction = goal.budgetFraction {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.overlay(0.06))
                        Capsule()
                            .fill(accent(status))
                            .frame(width: max(2, proxy.size.width * fraction))
                    }
                }
                .frame(height: 2)
                .padding(.horizontal, 12)
                .padding(.bottom, 7)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(statusLabel(goal, status)): \(goal.objective)")
    }

    @ViewBuilder
    private func statusGlyph(_ status: ActiveGoal.Status) -> some View {
        switch status {
        case .achieved:
            CheckIcon(size: 13).foregroundColor(accent(status))
        default:
            LucideIcon(.circleDot, size: 13).foregroundColor(accent(status))
        }
    }

    private func bannerButton(_ icon: LucideIcon.Kind, label: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideIcon(icon, size: 13)
                .foregroundColor(destructive ? Palette.danger.opacity(0.85)
                                              : Color.overlay(0.55))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHint(label)
        .accessibilityLabel(label)
    }

    // MARK: - Presentation helpers

    private func accent(_ status: ActiveGoal.Status) -> Color {
        switch status {
        case .active:   return Palette.pastelBlue
        case .paused:   return Color.overlay(0.5)
        case .limited:  return Palette.warning
        case .achieved: return Palette.pastelBlue
        }
    }

    private func statusLabel(_ goal: ActiveGoal, _ status: ActiveGoal.Status) -> String {
        switch status {
        case .active:   return L10n.t("Goal active")
        case .paused:   return L10n.t("Goal paused")
        case .limited:  return L10n.t("Goal over budget")
        case .achieved:
            let secs = goal.achievedAt.map { Int($0.timeIntervalSince(goal.createdAt)) } ?? goal.elapsedSeconds
            return "\(L10n.t("Goal achieved")) · \(duration(secs))"
        }
    }

    private func short(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }

    private func duration(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(sec)s" }
        return "\(sec)s"
    }
}

// MARK: - Goal edit / create sheet

struct GoalEditSheet: View {
    let chatId: UUID
    /// nil when creating a brand-new goal.
    let existing: ActiveGoal?
    let onClose: () -> Void

    @State private var objective: String
    @State private var budgetText: String

    init(chatId: UUID, existing: ActiveGoal?, onClose: @escaping () -> Void) {
        self.chatId = chatId
        self.existing = existing
        self.onClose = onClose
        _objective = State(initialValue: existing?.objective ?? "")
        _budgetText = State(initialValue: existing?.tokenBudget.map(String.init) ?? "")
    }

    private var canSave: Bool {
        !objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existing == nil ? L10n.t("Set a goal") : L10n.t("Edit goal"))
                .font(BodyFont.system(size: 16, wght: 600))
                .foregroundColor(Palette.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t("Objective"))
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                TextEditor(text: $objective)
                    .font(BodyFont.system(size: 13))
                    .foregroundColor(Palette.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(height: 78)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.overlay(0.06))
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t("Token budget (optional)"))
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                TextField(L10n.t("No limit"), text: $budgetText)
                    .textFieldStyle(.plain)
                    .font(BodyFont.system(size: 13, design: .monospaced))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(Color.overlay(0.06))
                    )
                    .onChange(of: budgetText) {
                        budgetText = budgetText.filter(\.isNumber)
                    }
            }

            HStack {
                Spacer()
                Button(L10n.t("Cancel")) { onClose() }
                    .buttonStyle(.plain)
                    .foregroundColor(Palette.textSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 7)

                Button(L10n.t("Save")) {
                    GoalStore.shared.setGoal(
                        for: chatId,
                        objective: objective,
                        tokenBudget: Int(budgetText)
                    )
                    onClose()
                }
                .buttonStyle(.plain)
                .foregroundColor(canSave ? Color.gray(light: 0.96, dark: 0.06) : Color.overlay(0.5))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(canSave ? Color.gray(light: 0.12, dark: 0.94) : Color.overlay(0.12)))
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(Palette.background)
    }
}
