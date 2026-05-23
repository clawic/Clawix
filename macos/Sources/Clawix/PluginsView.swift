import SwiftUI

struct PluginsView: View {
    @EnvironmentObject var appState: AppState
    @State private var search = ""

    private var query: String { search.trimmingCharacters(in: .whitespaces).lowercased() }

    private func matches(_ plugin: Plugin) -> Bool {
        query.isEmpty
            || plugin.name.lowercased().contains(query)
            || plugin.description.lowercased().contains(query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageHeader("Plugins")

            TextField(L10n.t("Search plugins"), text: $search)
                .textFieldStyle(.plain)
                .font(BodyFont.system(size: 13))
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .padding(.horizontal, 24)
                .padding(.bottom, 10)

            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach($appState.plugins) { $plugin in
                        if matches(plugin) {
                            PluginRow(plugin: $plugin)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .thinScrollers()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}

private struct PluginRow: View {
    @Binding var plugin: Plugin

    var body: some View {
        HStack(spacing: 14) {
            LucideIcon.auto(plugin.iconName, size: 11)
                .foregroundColor(Palette.textSecondary)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.cardFill)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(plugin.name)
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text(plugin.description)
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textTertiary)
            }

            Spacer()

            PillToggle(isOn: $plugin.isEnabled)
                .accessibilityLabel(L10n.a11yPluginToggle(name: plugin.name, isOn: plugin.isEnabled))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Palette.border, lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(plugin.name)
    }

}
