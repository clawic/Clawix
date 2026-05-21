import Foundation

extension AppState {
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
                let chatByThreadId = Dictionary(uniqueKeysWithValues: searchableSummaries.compactMap { summary in
                    summary.clawixThreadId.map { ($0, summary.id) }
                })
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
