import SwiftUI
import Combine

// MARK: - Welcome role
//
// A one-time, lightweight personalization: the user picks the kind of work
// they do so the home offers more relevant starting points. It is inline on
// the home (a small strip), not a blocking modal, and is fully optional — the
// strip can be dismissed and suggestions still work. The chosen role tailors
// the general (no-project) ambient suggestions.

enum HomeRole: String, CaseIterable, Codable, Identifiable {
    case engineering
    case design
    case data
    case product
    case writing
    case learning
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .engineering: return L10n.t("Engineering")
        case .design:      return L10n.t("Design")
        case .data:        return L10n.t("Data")
        case .product:     return L10n.t("Product")
        case .writing:     return L10n.t("Writing")
        case .learning:    return L10n.t("Learning")
        case .other:       return L10n.t("Something else")
        }
    }

    var icon: LucideIcon.Kind {
        switch self {
        case .engineering: return .terminal
        case .design:      return .image
        case .data:        return .database
        case .product:     return .listChecks
        case .writing:     return .fileText
        case .learning:    return .globe
        case .other:       return .circleDot
        }
    }

    /// Original, neutral starting points tailored to the role. Used for the
    /// general (no-project) home when a role is set.
    var seeds: [String] {
        switch self {
        case .engineering:
            return ["Scaffold a small tool from scratch",
                    "Help me debug a tricky error",
                    "Review a design before I build it"]
        case .design:
            return ["Turn a rough idea into a layout",
                    "Critique a screen I'm working on",
                    "Generate a color and type system"]
        case .data:
            return ["Explore a dataset and find patterns",
                    "Draft an analysis plan with me",
                    "Clean and reshape some messy data"]
        case .product:
            return ["Outline a spec for a new feature",
                    "Pressure-test an idea with me",
                    "Draft a launch checklist"]
        case .writing:
            return ["Draft something from a few notes",
                    "Tighten a piece I already wrote",
                    "Brainstorm angles for a topic"]
        case .learning:
            return ["Teach me a concept with examples",
                    "Build me a study plan",
                    "Quiz me on what I'm learning"]
        case .other:
            return ["Plan my day around one goal",
                    "Help me think through a decision",
                    "Organize my notes and to-dos"]
        }
    }
}

@MainActor
final class WelcomeRoleStore: ObservableObject {
    static let shared = WelcomeRoleStore()

    @Published var selectedRole: HomeRole? { didSet { persist() } }
    @Published var dismissed: Bool { didSet { persist() } }

    private let roleKey = "clawix.home.role"
    private let dismissKey = "clawix.home.role.dismissed"

    private init() {
        if let raw = UserDefaults.standard.string(forKey: roleKey) {
            selectedRole = HomeRole(rawValue: raw)
        }
        dismissed = UserDefaults.standard.bool(forKey: dismissKey)
    }

    /// Show the inline picker only until the user picks or dismisses it.
    var shouldOffer: Bool { selectedRole == nil && !dismissed }

    func choose(_ role: HomeRole) { selectedRole = role }
    func dismiss() { dismissed = true }

    private func persist() {
        UserDefaults.standard.set(selectedRole?.rawValue, forKey: roleKey)
        UserDefaults.standard.set(dismissed, forKey: dismissKey)
    }
}

// MARK: - Inline role picker strip

struct RolePickerStrip: View {
    @ObservedObject private var store = WelcomeRoleStore.shared

    var body: some View {
        if store.shouldOffer {
            VStack(spacing: 10) {
                HStack {
                    Text(L10n.t("What do you work on?"))
                        .font(BodyFont.system(size: 12.5, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { store.dismiss() }
                    } label: {
                        XIcon(size: 11)
                            .foregroundColor(Color.white.opacity(0.45))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("Dismiss"))
                }

                FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(HomeRole.allCases) { role in
                        RoleChip(role: role) {
                            withAnimation(.easeOut(duration: 0.18)) { store.choose(role) }
                        }
                    }
                }
            }
            .frame(maxWidth: 680)
            .transition(.opacity)
        }
    }
}

private struct RoleChip: View {
    let role: HomeRole
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                LucideIcon(role.icon, size: 12)
                    .foregroundColor(Color.white.opacity(hovering ? 0.8 : 0.55))
                Text(role.label)
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Color.white.opacity(hovering ? 0.95 : 0.8))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.09 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel(role.label)
    }
}
