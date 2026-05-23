import SwiftUI
import Combine

// MARK: - Parallel attempts
//
// Lets the user ask the agent for more than one independent attempt at the
// next turn so they can compare results. The selector cycles 1→2→3 and stays
// quiet (dim) at the default of one attempt. The runtime reads `attempts` when
// dispatching the turn; at 1 it behaves exactly as before.

@MainActor
final class ComposerAttemptsStore: ObservableObject {
    static let shared = ComposerAttemptsStore()

    static let maxAttempts = 3

    @Published var attempts: Int = 1

    private let defaultsKey = "clawix.composer.attempts"

    private init() {
        let saved = UserDefaults.standard.integer(forKey: defaultsKey)
        if (1...Self.maxAttempts).contains(saved) { attempts = saved }
    }

    func cycle() {
        attempts = attempts >= Self.maxAttempts ? 1 : attempts + 1
        UserDefaults.standard.set(attempts, forKey: defaultsKey)
    }

    func reset() {
        guard attempts != 1 else { return }
        attempts = 1
        UserDefaults.standard.set(1, forKey: defaultsKey)
    }
}

struct AttemptsSelector: View {
    @ObservedObject private var store = ComposerAttemptsStore.shared
    @State private var hovering = false

    private var active: Bool { store.attempts > 1 }

    var body: some View {
        Button { store.cycle() } label: {
            Text(String(
                format: String(localized: "%@×", bundle: AppLocale.bundle, locale: AppLocale.current),
                "\(store.attempts)"
            ))
                .font(BodyFont.system(size: 11.5, wght: 600))
                .monospacedDigit()
                // Active reads as a neutral lift (the count itself is the
                // signal), not a brand-colour fill, so the composer footer
                // stays calm and uniform with the composer chrome
                // (STYLE.md §2.3 — brand never fills an action surface).
                .foregroundColor(active ? Color.gray(light: 0.16, dark: 0.92)
                                        : Color.overlay(hovering ? 0.7 : 0.45))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.overlay(active ? (hovering ? 0.09 : 0.06)
                                                   : (hovering ? 0.06 : 0.0)))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.16), value: store.attempts)
        .hoverHint(L10n.t("Parallel attempts"))
        .accessibilityLabel("\(L10n.t("Parallel attempts")): \(store.attempts)")
    }
}
