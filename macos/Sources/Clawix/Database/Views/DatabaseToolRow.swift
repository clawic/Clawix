import SwiftUI

/// Sidebar entry for a curated database collection. Mirrors
/// `SecretsToolRow` so the row metrics stay aligned.
struct DatabaseToolRow: View {
    let title: String
    let systemIcon: String
    let route: SidebarRoute
    let isSelected: Bool
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 11) {
                LucideIcon.auto(systemIcon, size: 12.5)
                    .frame(width: 15, height: 15)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(BodyFont.system(size: 13.5, wght: 500))
                    .foregroundColor(labelColor)
                Spacer(minLength: 6)
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .id("\(title)-\(isSelected)")
    }

    private var iconColor: Color {
        if isSelected { return .white }
        return (hovered ? Color.gray(light: 0.14, dark: 0.92) : Color.gray(light: 0.27, dark: 0.78))
    }

    private var labelColor: Color {
        isSelected ? .white : Color.gray(light: 0.14, dark: 0.92)
    }

    private var backgroundFill: Color {
        if isSelected { return Color.overlay(0.06) }
        if hovered    { return Color.overlay(0.035) }
        return .clear
    }
}
