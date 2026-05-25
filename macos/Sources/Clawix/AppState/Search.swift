import Foundation

extension AppState {
    struct QuickSwitchChatHeader: Identifiable, Equatable {
        let id: String
        let title: String
        let projectName: String?
        let updatedAt: Date
        let session: ClawJSSessionsClient.SessionRecord
    }

    func performSearch(_ query: String) {
        searchQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            searchResultRoutes = [:]
            return
        }

        var results: [String] = []
        var routes: [String: SidebarRoute] = [:]
        var seen: Set<String> = []
        let searchableSummaries = (chatStore.summaries + chatStore.archivedSummaries)
            .filter { !$0.isQuickAskTemporary && !$0.isSideChat }

        func append(_ text: String, chatId: UUID) {
            guard results.count < 50 else { return }
            let unique = uniqueSearchResult(text, seen: &seen)
            results.append(unique)
            routes[unique] = .chat(chatId)
        }

        for summary in searchableSummaries {
            if summary.title.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                append("\(summary.title) — title match", chatId: summary.id)
            }
            guard results.count < 50 else { break }
        }

        searchResults = results
        searchResultRoutes = routes

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let hits = try await self.clawJSSessionsClientFactory().searchMessages(
                    query: trimmed,
                    limit: 50
                )
                guard self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
                var merged = results
                var mergedRoutes = routes
                var mergedSeen = seen
                let chatByThreadId = self.chatSummaryIdByThreadId(searchableSummaries)
                for hit in hits where merged.count < 50 {
                    guard let chatId = chatByThreadId[hit.session.id] else { continue }
                    let role = hit.message.role == "user" ? "User" : "Assistant"
                    let snippet = hit.snippet
                        .replacingOccurrences(of: "<<", with: "")
                        .replacingOccurrences(of: ">>", with: "")
                    let unique = self.uniqueSearchResult("\(hit.session.title) — \(role): \(snippet)", seen: &mergedSeen)
                    merged.append(unique)
                    mergedRoutes[unique] = .chat(chatId)
                }
                self.searchResults = merged
                self.searchResultRoutes = mergedRoutes
            } catch {
                // Leave title results in place. Global message search is
                // backed by the ClawJS sessions sidecar and should not
                // hydrate every transcript into AppState as a fallback.
            }
        }
    }

    func quickSwitchSessionHeaders(
        query: String,
        scopedProject: Project? = nil,
        limit: Int = 9
    ) async -> [QuickSwitchChatHeader] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        do {
            let response = try await clawJSSessionsClientFactory().quickSwitchSessions(
                query: trimmed,
                projectPath: scopedProject?.path,
                includeArchived: false,
                limit: limit,
                offset: 0
            )
            guard response.source == "sessions.quick_switch",
                  response.searchedMessageHistory == false else {
                return []
            }
            let projectsByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
            return response.items
                .filter { !$0.archived && $0.sidebarVisible }
                .map { session in
                    let root = scopedProject?.path
                        ?? rootPath(
                            threadId: session.id,
                            cwd: session.cwd ?? session.projectPath,
                            projectByPath: projectsByPath
                        )
                    let project = root.flatMap { projectsByPath[$0] }
                    return QuickSwitchChatHeader(
                        id: session.id,
                        title: Self.quickSwitchTitle(for: session),
                        projectName: project?.name,
                        updatedAt: Self.sessionDate(milliseconds: session.lastMessageAt ?? session.createdAt),
                        session: session
                    )
                }
        } catch {
            return []
        }
    }

    @discardableResult
    func openQuickSwitchSession(_ header: QuickSwitchChatHeader) -> Bool {
        let chat = materializeQuickSwitchSession(header.session)
        navigate(to: .chat(chat.id))
        return true
    }

    private func uniqueSearchResult(_ text: String, seen: inout Set<String>) -> String {
        guard seen.contains(text) else {
            seen.insert(text)
            return text
        }
        var counter = 2
        while seen.contains("\(text) (\(counter))") {
            counter += 1
        }
        let unique = "\(text) (\(counter))"
        seen.insert(unique)
        return unique
    }

    private func searchSnippet(in content: String, around range: Range<String.Index>) -> String {
        let start = content.startIndex
        let end = content.endIndex
        let lower = content.index(range.lowerBound, offsetBy: -80, limitedBy: start) ?? start
        let upper = content.index(range.upperBound, offsetBy: 80, limitedBy: end) ?? end
        var snippet = String(content[lower..<upper])
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        while snippet.contains("  ") {
            snippet = snippet.replacingOccurrences(of: "  ", with: " ")
        }
        if lower > start { snippet = "…" + snippet }
        if upper < end { snippet += "…" }
        return snippet.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func materializeQuickSwitchSession(_ session: ClawJSSessionsClient.SessionRecord) -> Chat {
        let projectByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
        let root = rootPath(
            threadId: session.id,
            cwd: session.cwd ?? session.projectPath,
            projectByPath: projectByPath
        )
        let projectId = root.flatMap { projectByPath[$0]?.id }
        let old = (chats + archivedChats).first { $0.clawixThreadId == session.id }
        let archived = session.archived
        let chat = Chat(
            id: old?.id ?? UUID(uuidString: session.id) ?? UUID(),
            title: Self.quickSwitchTitle(for: session),
            messages: [],
            createdAt: Self.sessionDate(milliseconds: session.lastMessageAt ?? session.createdAt),
            clawixThreadId: session.id,
            rolloutPath: old?.rolloutPath,
            historyHydrated: old?.historyHydrated ?? false,
            hasActiveTurn: old?.hasActiveTurn ?? false,
            projectId: projectId,
            isArchived: archived,
            isPinned: !archived && session.pinned,
            hasUnreadCompletion: old?.hasUnreadCompletion ?? false,
            cwd: session.cwd ?? session.projectPath,
            hasGitRepo: old?.hasGitRepo ?? false,
            branch: old?.branch ?? session.branch,
            availableBranches: old?.availableBranches ?? [],
            uncommittedFiles: old?.uncommittedFiles
        )

        if let index = chats.firstIndex(where: { $0.id == chat.id || $0.clawixThreadId == session.id }) {
            if archived {
                chats.remove(at: index)
                upsertArchivedQuickSwitchChat(chat)
            } else {
                chats[index] = chat
            }
        } else if let index = archivedChats.firstIndex(where: { $0.id == chat.id || $0.clawixThreadId == session.id }) {
            if archived {
                archivedChats[index] = chat
            } else {
                archivedChats.remove(at: index)
                chats.insert(chat, at: 0)
            }
        } else if archived {
            upsertArchivedQuickSwitchChat(chat)
        } else {
            chats.insert(chat, at: 0)
        }

        return chat
    }

    private func upsertArchivedQuickSwitchChat(_ chat: Chat) {
        if let index = archivedChats.firstIndex(where: { $0.id == chat.id || $0.clawixThreadId == chat.clawixThreadId }) {
            archivedChats[index] = chat
        } else {
            archivedChats.insert(chat, at: 0)
            if archivedChats.count > Self.archivedSidebarLimit {
                archivedChats = Array(archivedChats.prefix(Self.archivedSidebarLimit))
            }
        }
    }

    private static func sessionDate(milliseconds value: Int64) -> Date {
        let seconds = value > 10_000_000_000 ? Double(value) / 1000.0 : Double(value)
        return Date(timeIntervalSince1970: seconds)
    }

    private static func quickSwitchTitle(for session: ClawJSSessionsClient.SessionRecord) -> String {
        let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Conversation" : title
    }

    // MARK: - Find (in-page)

    /// True when ⌘F has somewhere meaningful to land. Only a chat view
    /// can hold a find bar today; routes like `.home`, `.search`, or
    /// `.settings` do not have searchable transcripts so the menu item
    /// disables there.
    var canOpenFindBar: Bool {
        if case .chat = currentRoute { return true }
        return false
    }

    func openFindBar() {
        guard case .chat(let id) = currentRoute else { return }
        findChatId = id
        isFindBarOpen = true
    }

    func closeFindBar() {
        isFindBarOpen = false
        findQuery = ""
        findMatches = []
        currentFindIndex = 0
        findChatId = nil
        isFinding = false
        findDebounce?.cancel()
        findDebounce = nil
    }

    /// Updates `findQuery` and recomputes matches over the active chat
    /// transcript with a short debounce so each keystroke doesn't burn a
    /// full pass over the message list. The spinner stays on while the
    /// debounce is pending so the bar shows visible feedback even on
    /// instant searches.
    func updateFindQuery(_ q: String) {
        findQuery = q
        findDebounce?.cancel()
        guard !q.isEmpty else {
            findMatches = []
            currentFindIndex = 0
            isFinding = false
            return
        }
        isFinding = true
        let work = DispatchWorkItem { [weak self] in
            self?.runFindNow()
        }
        findDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(260), execute: work)
    }

    private func runFindNow() {
        guard let chatId = findChatId, let chat = chat(byId: chatId) else {
            findMatches = []
            currentFindIndex = 0
            isFinding = false
            return
        }
        let q = findQuery
        guard !q.isEmpty else {
            findMatches = []
            currentFindIndex = 0
            isFinding = false
            return
        }
        var out: [FindMatch] = []
        let messages = chatStore.transcript(for: chatId)?.messages ?? chat.messages
        for msg in messages {
            let haystack = msg.content as NSString
            var searchRange = NSRange(location: 0, length: haystack.length)
            while searchRange.location < haystack.length {
                let r = haystack.range(of: q, options: [.caseInsensitive], range: searchRange)
                if r.location == NSNotFound { break }
                out.append(FindMatch(messageId: msg.id, range: r))
                let next = r.location + max(r.length, 1)
                if next >= haystack.length { break }
                searchRange = NSRange(location: next, length: haystack.length - next)
            }
        }
        findMatches = out
        currentFindIndex = out.isEmpty ? 0 : 0
        isFinding = false
    }

    func nextFindMatch() {
        guard !findMatches.isEmpty else { return }
        currentFindIndex = (currentFindIndex + 1) % findMatches.count
    }

    func prevFindMatch() {
        guard !findMatches.isEmpty else { return }
        currentFindIndex = (currentFindIndex - 1 + findMatches.count) % findMatches.count
    }

    var currentFindMatch: FindMatch? {
        guard !findMatches.isEmpty,
              currentFindIndex >= 0,
              currentFindIndex < findMatches.count else { return nil }
        return findMatches[currentFindIndex]
    }
}
