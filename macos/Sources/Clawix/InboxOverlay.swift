import SwiftUI

// MARK: - Inbox overlay
//
// A compact panel listing recent activity items (see `InboxStore`). Unread
// items lead with a brand dot; tapping one marks it read and, when it carries a
// thread, opens that chat. Empty by default until the runtime leaves items.

struct InboxOverlay: View {
    let onClose: () -> Void

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store = InboxStore.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            if store.items.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(width: 440, height: 560)
        .background(Palette.background)
        .onAppear { store.refresh() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(L10n.t("Inbox"))
                .font(BodyFont.system(size: 15, wght: 600))
                .foregroundColor(Palette.textPrimary)
            if store.unreadCount > 0 {
                Text("\(store.unreadCount)")
                    .font(BodyFont.system(size: 10.5, wght: 600))
                    .monospacedDigit()
                    .foregroundColor(Color(white: 0.06))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Palette.pastelBlue))
            }
            Spacer()
            if store.unreadCount > 0 {
                Button(L10n.t("Mark all read")) { store.markAllRead() }
                    .buttonStyle(.plain)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Button { onClose() } label: {
                XIcon(size: 12)
                    .foregroundColor(Color.white.opacity(0.5))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("Close"))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(store.items.prefix(100)) { item in
                    InboxRow(item: item) { open(item) }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            LucideIcon(.inbox, size: 30)
                .foregroundColor(Color.white.opacity(0.28))
            Text(L10n.t("Nothing here yet"))
                .font(BodyFont.system(size: 13.5, wght: 500))
                .foregroundColor(Palette.textSecondary)
            Text(L10n.t("Results from automations and background work will show up here."))
                .font(BodyFont.system(size: 12))
                .foregroundColor(Palette.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func open(_ item: InboxItem) {
        store.markRead(item.id)
        if let threadId = item.threadId, let uuid = UUID(uuidString: threadId) {
            appState.navigate(to: .chat(uuid))
            onClose()
        }
    }
}

private struct InboxRow: View {
    let item: InboxItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(item.read ? Color.clear : Palette.pastelBlue)
                    .frame(width: 6, height: 6)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(BodyFont.system(size: 13, wght: item.read ? 500 : 600))
                        .foregroundColor(Palette.textPrimary.opacity(item.read ? 0.82 : 1))
                        .lineLimit(1)
                    if let summary = item.summary, !summary.isEmpty {
                        Text(summary)
                            .font(BodyFont.system(size: 12))
                            .foregroundColor(Palette.textSecondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 6) {
                        if let source = item.source, !source.isEmpty {
                            Text(source)
                                .font(BodyFont.system(size: 10.5, wght: 500))
                                .foregroundColor(Palette.textSecondary)
                        }
                        Text(relativeTime(item.createdAt))
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.05 : 0.0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return L10n.t("now") }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days == 1 { return L10n.t("yesterday") }
        return "\(days)d"
    }
}
