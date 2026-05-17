import SwiftUI

struct PowerModeSummaryRow: View {
    @ObservedObject var store: PowerModeStore
    @State private var sheetOpen = false

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text("Power Mode")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            HStack(spacing: 10) {
                PillToggle(isOn: Binding(
                    get: { store.enabled },
                    set: { store.enabled = $0 }
                ))
                Button {
                    sheetOpen = true
                } label: {
                    Text("Manage")
                        .font(BodyFont.system(size: 12, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule(style: .continuous).fill(Color(white: 0.165)))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $sheetOpen) {
            PowerModeListSheet(store: store, isPresented: $sheetOpen)
        }
    }

    private var detail: LocalizedStringKey {
        let total = store.configs.count
        let enabled = store.configs.filter(\.enabled).count
        if !store.enabled {
            return "Off. Profile-based overrides per app or website ignored until enabled."
        }
        if let active = store.activeConfig {
            return "On · \(active.emoji) \(active.name) active for the foreground app"
        }
        return "On · \(enabled)/\(total) profiles enabled, no match for the foreground app"
    }
}
