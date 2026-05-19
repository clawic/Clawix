import SwiftUI

struct ContactsScreen: View {

    @StateObject private var store = ContactsStore()

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ContactsToolbar(store: store)
                HStack(spacing: 0) {
                    ContactsSubSidebar(store: store)
                    contentColumns
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(ContactsTokens.Surface.window)
            .task { await store.bootstrap() }
            .onDisappear {
                store.cancelSurfaceWork()
            }

            if store.isCreating {
                modalScrim {
                    store.endCreate()
                }
                ContactCreateModal(store: store) {
                    store.endCreate()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            if store.isMergeOpen {
                modalScrim {
                    store.isMergeOpen = false
                }
                MergeDuplicatesView(store: store) {
                    store.isMergeOpen = false
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            if let id = store.editingSmartGroupID,
               let group = store.groupsByID[id] {
                modalScrim {
                    store.editingSmartGroupID = nil
                }
                SmartGroupConfigView(store: store, draft: group) {
                    store.editingSmartGroupID = nil
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(ContactsTokens.Motion.editToggle, value: store.isCreating)
        .animation(ContactsTokens.Motion.editToggle, value: store.isMergeOpen)
        .animation(ContactsTokens.Motion.editToggle, value: store.editingSmartGroupID)
    }

    @ViewBuilder
    private var contentColumns: some View {
        switch store.access {
        case .unknown, .requesting:
            centered("Loading contacts…")
        case .denied(let reason):
            centered("Contacts access denied", subtitle: reason)
        case .unavailable:
            centered("Contacts unavailable")
        case .granted:
            HStack(spacing: 0) {
                ContactsList(store: store)
                detailColumn
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        Group {
            if let contact = store.selectedContact {
                if store.isEditing {
                    ContactEditView(
                        store: store,
                        draft: contact,
                        isNew: false,
                        onCancel: { store.cancelEdit() },
                        onSave: { saved in
                            Task { await store.commit(saved) }
                        }
                    )
                    .transition(.opacity)
                    .id("edit-\(contact.id)")
                } else {
                    ContactDetail(store: store, contact: contact)
                        .transition(.opacity)
                        .id("read-\(contact.id)")
                }
            } else {
                centered("No Contact Selected",
                         subtitle: store.contacts.isEmpty
                            ? "Add a new contact to get started."
                            : "Pick a contact from the list to see details.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ContactsTokens.Surface.detail)
            }
        }
        .frame(minWidth: ContactsTokens.Geometry.detailMinWidth, maxWidth: .infinity, maxHeight: .infinity)
        .animation(ContactsTokens.Motion.editToggle, value: store.isEditing)
        .animation(ContactsTokens.Motion.selection, value: store.selectedContactID)
    }

    private func centered(_ title: String, subtitle: String? = nil) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: ContactsTokens.TypeSize.emptyTitle, weight: .medium))
                .foregroundColor(ContactsTokens.Ink.primary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: ContactsTokens.TypeSize.emptySubtitle))
                    .foregroundColor(ContactsTokens.Ink.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func modalScrim(onTap: @escaping () -> Void) -> some View {
        Color.black.opacity(0.4)
            .ignoresSafeArea()
            .onTapGesture(perform: onTap)
            .transition(.opacity)
    }
}
