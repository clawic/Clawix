import SwiftUI

/// 3-pane Memory browser: Topics sidebar, filtered notes list, detail pane.
struct MemoryHomeView: View {

    @ObservedObject var store: MemoryStore
    let onSelectSection: (MemoryScreen.Section) -> Void

    @State private var groupBy: MemorySidebar.GroupBy = .type
    @State private var selectedTopic: MemorySidebar.TopicID? = nil
    @State private var selectedScopes: Set<MemorySidebar.ScopeAxis> = []
    @State private var selectedNoteId: String? = nil
    @State private var searchText: String = ""
    @State private var editTarget: ClawJSMemoryClient.MemoryNote? = nil
    @State private var deleteTarget: ClawJSMemoryClient.MemoryNote? = nil
    @State private var actionError: String?

    var body: some View {
        HStack(spacing: 0) {
            MemorySidebar(
                groupBy: $groupBy,
                selectedTopic: $selectedTopic,
                selectedScopes: $selectedScopes,
                notes: store.notes,
                stats: store.stats,
                pendingCaptures: pendingCapturesCount,
                onOpenCaptures: { onSelectSection(.captures) },
                onOpenSettings: { onSelectSection(.settings) }
            )
            .frame(width: 240)
            CardDivider()
            MemoryListPane(
                searchText: $searchText,
                isSearching: store.isSearching,
                searchResults: store.lastSearch?.results ?? [],
                notes: filteredNotes,
                selectedNoteId: $selectedNoteId,
                onSearchSubmit: { store.search(searchText) },
                onSearchClear: {
                    searchText = ""
                    store.clearSearch()
                },
                onEdit: { note in editTarget = note },
                onDelete: { note in
                    deleteTarget = note
                }
            )
            .frame(minWidth: 320)
            CardDivider()
            MemoryDetailPane(
                note: selectedNote,
                onEdit: { note in editTarget = note },
                onDelete: { note in
                    deleteTarget = note
                }
            )
            .frame(maxWidth: .infinity)
        }
        .onChange(of: searchText) { _, newValue in
            store.search(newValue)
        }
        .sheet(item: $editTarget) { note in
            MemoryEditSheet(
                store: store,
                mode: .edit(note),
                onDismiss: { editTarget = nil }
            )
        }
        .alert("Delete memory?", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("Delete", role: .destructive) {
                guard let note = deleteTarget else { return }
                let id = note.id
                Task {
                    do {
                        _ = try await store.delete(id: id)
                        await MainActor.run {
                            if selectedNoteId == id { selectedNoteId = nil }
                            deleteTarget = nil
                        }
                    } catch {
                        await MainActor.run {
                            actionError = error.localizedDescription
                            deleteTarget = nil
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                deleteTarget = nil
            }
        } message: {
            Text(deleteTarget.map { "This permanently deletes \"\($0.title)\" from Memory." } ?? "")
        }
        .alert("Memory action failed", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {
                actionError = nil
            }
        } message: {
            Text(actionError ?? "")
        }
    }

    private var pendingCapturesCount: Int {
        store.captures.filter { $0.promotedAt == nil }.count
    }

    /// Filters `store.notes` by topic + scope. Search is handled by
    /// the daemon and surfaces in `store.lastSearch`; the list pane
    /// shows whichever side is active (search vs filter).
    private var filteredNotes: [ClawJSMemoryClient.MemoryNote] {
        var result = store.notes
        if let topic = selectedTopic {
            switch topic {
            case .all:
                break
            case .type(let value):
                result = result.filter { $0.type == value || $0.semanticKind == value }
            case .entity(let entityId):
                result = result.filter { note in
                    note.frontmatter.contains { (_, value) in
                        if case .string(let s) = value { return s == entityId }
                        if case .array(let arr) = value {
                            return arr.contains { if case .string(let s) = $0 { return s == entityId } else { return false } }
                        }
                        return false
                    }
                }
            case .tag(let tag):
                result = result.filter { $0.tags.contains(tag) }
            }
        }
        if !selectedScopes.isEmpty {
            result = result.filter { note in
                selectedScopes.allSatisfy { axis in
                    switch axis {
                    case .user: return note.scopeUser != nil
                    case .agent: return note.scopeAgent != nil
                    case .project: return note.scopeProject != nil
                    }
                }
            }
        }
        return result
    }

    private var selectedNote: ClawJSMemoryClient.MemoryNote? {
        guard let id = selectedNoteId else { return store.notes.first }
        return store.notes.first(where: { $0.id == id })
    }
}
