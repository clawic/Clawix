import SwiftUI

// MARK: - Companion
//
// A small, original desktop companion drawn entirely in SwiftUI (no sprite
// assets). It lives in a frameless floating window (see `PetController`) and
// idles with a gentle bob + breathe and periodic blinks; tapping it makes it
// hop. Honors reduce-motion. Hovering reveals a tuck-away control.

struct PetView: View {
    let onTuck: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var bob: CGFloat = 0
    @State private var breathe: CGFloat = 1
    @State private var eyeOpen: CGFloat = 1
    @State private var hop: CGFloat = 0
    @State private var hovering = false
    @State private var blinkTask: Task<Void, Never>?

    private let bodySize = CGSize(width: 78, height: 70)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            companion
                .offset(y: bob + hop)
                .scaleEffect(x: 1, y: breathe, anchor: .bottom)

            if hovering {
                Button(action: onTuck) {
                    XIcon(size: 9)
                        .foregroundColor(Color.overlay(0.7))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("Tuck away"))
                .offset(x: 2, y: -2)
                .transition(.opacity)
            }
        }
        .frame(width: 120, height: 120)
        .contentShape(Rectangle())
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.14)) { hovering = isHovering }
        }
        .onTapGesture { reactToTap() }
        .onAppear { startIdle() }
        .onDisappear { blinkTask?.cancel() }
        .accessibilityLabel(L10n.t("Companion"))
        .accessibilityHint(L10n.t("Tap to play, or tuck it away"))
    }

    private var companion: some View {
        ZStack {
            // Soft shadow grounding it on the desktop.
            Ellipse()
                .fill(Color.black.opacity(0.22))
                .frame(width: bodySize.width * 0.7, height: 10)
                .blur(radius: 4)
                .offset(y: bodySize.height / 2 + 8 - (bob + hop) * 0.4)

            // Body.
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.gray(light: 0.88, dark: 0.20), Color.gray(light: 0.945, dark: 0.12)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: bodySize.width, height: bodySize.height)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Palette.pastelBlue.opacity(0.30), lineWidth: 1)
                )
                .overlay(
                    // Faint top highlight.
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.overlay(0.10), Color.clear],
                                startPoint: .top, endPoint: .center
                            )
                        )
                        .frame(width: bodySize.width - 8, height: bodySize.height - 8)
                )
                .shadow(color: .black.opacity(0.35), radius: 10, y: 6)

            // Face.
            HStack(spacing: 14) {
                eye
                eye
            }
            .offset(y: -2)
        }
    }

    private var eye: some View {
        Capsule()
            .fill(Color.overlay(0.92))
            .frame(width: 9, height: 14 * eyeOpen)
            .frame(height: 14, alignment: .center)
    }

    // MARK: - Motion

    private func startIdle() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
            bob = -4
        }
        withAnimation(.easeInOut(duration: 2.3).repeatForever(autoreverses: true)) {
            breathe = 1.03
        }
        scheduleBlink()
    }

    private func scheduleBlink() {
        blinkTask?.cancel()
        blinkTask = Task { @MainActor in
            while !Task.isCancelled {
                let delay = UInt64(Double.random(in: 2.6...5.0) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
                if Task.isCancelled { return }
                blink()
            }
        }
    }

    private func blink() {
        withAnimation(.easeInOut(duration: 0.08)) { eyeOpen = 0.12 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            withAnimation(.easeInOut(duration: 0.10)) { eyeOpen = 1 }
        }
    }

    private func reactToTap() {
        guard !reduceMotion else { blink(); return }
        withAnimation(.easeOut(duration: 0.16)) { hop = -14 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.5)) { hop = 0 }
        }
        blink()
    }
}
