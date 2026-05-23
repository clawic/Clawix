import SwiftUI

struct AndroidSimulatorIconButton: View {
    let systemName: String
    var enabled: Bool = true
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            LucideIcon.auto(systemName, size: 13)
                .foregroundColor(foreground)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hovered && enabled ? Color.overlay(0.07) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private var foreground: Color {
        if !enabled { return Color.gray(light: 0.84, dark: 0.32) }
        return hovered ? Color.gray(light: 0.14, dark: 0.92) : Color.gray(light: 0.31, dark: 0.72)
    }
}

struct AndroidSimulatorPanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BodyFont.system(size: 11.5, wght: 600))
            .foregroundColor(Palette.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed ? Color.overlay(0.20) : Color.overlay(0.12))
            )
    }
}
