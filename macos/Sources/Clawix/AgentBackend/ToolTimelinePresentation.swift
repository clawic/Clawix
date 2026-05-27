import Foundation

struct ToolTimelineRow: Identifiable, Equatable {
    let id: String
    let icon: String
    let text: String
}

struct ToolTimelineDetailRow: Identifiable, Equatable {
    let id: String
    let icon: String
    let text: String
    let status: WorkItemStatus
    let previewImagePath: String?
}

struct ToolTimelinePresentationSnapshot: Equatable {
    let version: Int
    let aggregateRows: [ToolTimelineRow]
    let runningCommands: [WorkItem]
    let accessibilityLabel: String

    init(
        version: Int = 0,
        aggregateRows: [ToolTimelineRow],
        runningCommands: [WorkItem],
        accessibilityLabel: String
    ) {
        self.version = version
        self.aggregateRows = aggregateRows
        self.runningCommands = runningCommands
        self.accessibilityLabel = accessibilityLabel
    }
}

enum ToolTimelinePresentation {
    static func aggregateRows(for items: [WorkItem]) -> [ToolTimelineRow] {
        snapshot(for: items).aggregateRows
    }

    static func detailRows(for items: [WorkItem]) -> [ToolTimelineDetailRow] {
        items.enumerated().map { index, item in
            detailRow(for: item, fallbackIndex: index)
        }
    }

    static func snapshot(for items: [WorkItem]) -> ToolTimelinePresentationSnapshot {
        buildSnapshot(version: 0, for: items)
    }

    static func snapshot(groupID: UUID, items: [WorkItem]) -> ToolTimelinePresentationSnapshot {
        ToolTimelinePresentationCache.shared.snapshot(groupID: groupID, items: items)
    }

    static func updatedSnapshot(
        groupID: UUID,
        previousItems: [WorkItem],
        currentSnapshot: ToolTimelinePresentationSnapshot?,
        applying item: WorkItem
    ) -> ToolTimelinePresentationSnapshot {
        ToolTimelinePresentationCache.shared.updatedSnapshot(
            groupID: groupID,
            previousItems: previousItems,
            currentSnapshot: currentSnapshot,
            applying: item
        )
    }

    fileprivate static func buildSnapshot(for items: [WorkItem]) -> ToolTimelinePresentationSnapshot {
        buildSnapshot(version: 0, for: items)
    }

    fileprivate static func buildSnapshot(
        version: Int,
        for items: [WorkItem]
    ) -> ToolTimelinePresentationSnapshot {
        let aggregateRows = buildAggregateRows(for: items)
        let runningCommands = items.filter { item in
            guard case .command = item.kind else { return false }
            return item.status == .inProgress
        }
        let runningText = runningCommands.compactMap { item -> String? in
            guard case .command(let text, _) = item.kind, let text, !text.isEmpty else {
                return nil
            }
            return text
        }
        let accessibilityLabel = AccessibilityText.clipped(
            (aggregateRows.map(\.text) + runningText).joined(separator: ". ")
        )
        return ToolTimelinePresentationSnapshot(
            version: version,
            aggregateRows: aggregateRows,
            runningCommands: runningCommands,
            accessibilityLabel: accessibilityLabel
        )
    }

    private static func buildAggregateRows(for items: [WorkItem]) -> [ToolTimelineRow] {
        var rows: [ToolTimelineRow] = []

        var readFiles = 0
        var listed = 0
        var searchedItems = 0
        var ranCommands = 0
        var changedPaths: Set<String> = []
        var unpathableFileChanges = 0
        var browserUsed = false
        var webSearchCount = 0
        var mcpTools: [(server: String, tool: String)] = []
        var dynamicTools: [String] = []
        var imageGenerations = 0
        var imageViews = 0
        var jsBrowserCount = 0
        var jsReplCount = 0

        for item in items {
            switch item.kind {
            case .command(_, let actions):
                if item.status == .inProgress { continue }
                let reads = actions.filter { $0 == .read }.count
                let lists = actions.filter { $0 == .listFiles }.count
                let searches = actions.filter { $0 == .search }.count
                if reads + lists + searches > 0 {
                    readFiles += reads
                    listed += lists
                    searchedItems += searches
                } else {
                    ranCommands += 1
                }
            case .fileChange(let paths):
                let nonEmptyPaths = paths.filter { !$0.isEmpty }
                if nonEmptyPaths.isEmpty {
                    unpathableFileChanges += 1
                } else {
                    changedPaths.formUnion(nonEmptyPaths)
                }
            case .webSearch:
                webSearchCount += 1
            case .mcpTool(let server, let tool):
                mcpTools.append((mcpServerBucket(server: server, tool: tool), tool))
            case .dynamicTool(let name):
                let lower = name.lowercased()
                if lower.contains("browser") {
                    browserUsed = true
                } else if lower.contains("web") {
                    webSearchCount += 1
                } else {
                    dynamicTools.append(name)
                }
            case .imageGeneration:
                imageGenerations += 1
            case .imageView:
                imageViews += 1
            case .jsCall(_, .browser):
                jsBrowserCount += 1
            case .jsCall(_, .repl):
                jsReplCount += 1
            case .jsReset:
                jsReplCount += 1
            }
        }

        let fileChanges = changedPaths.count + unpathableFileChanges
        let hasPrimaryWork = fileChanges > 0 || readFiles > 0 || listed > 0 || searchedItems > 0 || ranCommands > 0
        let totalBrowser = jsBrowserCount + (browserUsed ? 1 : 0)
        let inlineMcpServers = hasPrimaryWork ? Set(mcpTools.map(\.server)) : []

        if hasPrimaryWork {
            var parts: [String] = []
            if fileChanges > 0 { parts.append(L10n.editedFiles(fileChanges)) }
            if readFiles > 0 {
                parts.append(parts.isEmpty
                    ? L10n.exploredFiles(readFiles)
                    : L10n.exploredFilesInline(readFiles))
            }
            if searchedItems > 0 {
                parts.append(parts.isEmpty
                    ? L10n.exploredSearches(searchedItems)
                    : L10n.searchedItems(searchedItems))
            }
            if listed > 0 {
                parts.append(parts.isEmpty
                    ? L10n.listedItems(listed)
                    : L10n.listedItemsInline(listed))
            }
            if ranCommands > 0 {
                parts.append(parts.isEmpty
                    ? L10n.ranCommands(ranCommands)
                    : L10n.ranCommandsInline(ranCommands))
            }
            if totalBrowser > 0 {
                parts.append(String(localized: "used the browser", bundle: AppLocale.bundle, locale: AppLocale.current))
            }
            if webSearchCount > 0 {
                parts.append(L10n.searchedWebInline(webSearchCount))
            }
            for server in uniquePreservingOrder(mcpTools.map(\.server)) {
                parts.append(L10n.usedToolInline(prettyMcpServer(server)))
            }
            let icon: String
            if fileChanges > 0 {
                icon = "clawix.pencil"
            } else if listed > 0 {
                icon = "clawix.folderStack"
            } else if readFiles > 0 || searchedItems > 0 {
                icon = "magnifyingglass"
            } else {
                icon = "clawix.terminal"
            }
            rows.append(ToolTimelineRow(
                id: "exec",
                icon: icon,
                text: parts.joined(separator: ", ")
            ))
        }
        if totalBrowser > 0 && !hasPrimaryWork {
            let text: String
            if totalBrowser <= 1 {
                text = String(localized: "Used the browser", bundle: AppLocale.bundle, locale: AppLocale.current)
            } else {
                text = L10n.usedToolTimes("the browser", totalBrowser)
            }
            rows.append(ToolTimelineRow(
                id: "browser",
                icon: "clawix.cursor",
                text: text
            ))
        }
        if jsReplCount > 0 {
            let text = jsReplCount <= 1
                ? L10n.usedTool("Node Repl")
                : L10n.usedToolTimes("Node Repl", jsReplCount)
            rows.append(ToolTimelineRow(
                id: "nodeRepl",
                icon: "command",
                text: text
            ))
        }
        if webSearchCount > 0 && !hasPrimaryWork {
            let text = L10n.searchedWeb(webSearchCount)
            rows.append(ToolTimelineRow(id: "webSearch", icon: "clawix.globe", text: text))
        }

        var serverOrder: [String] = []
        var serverCounts: [String: Int] = [:]
        for mcp in mcpTools where !mcp.server.isEmpty && !inlineMcpServers.contains(mcp.server) {
            if serverCounts[mcp.server] == nil { serverOrder.append(mcp.server) }
            serverCounts[mcp.server, default: 0] += 1
        }
        for (idx, server) in serverOrder.enumerated() {
            let count = serverCounts[server] ?? 1
            let pretty = prettyMcpServer(server)
            let text = count <= 1 ? L10n.usedTool(pretty) : L10n.usedToolTimes(pretty, count)
            rows.append(ToolTimelineRow(
                id: "mcp\(idx)",
                icon: isComputerUseMcpServer(server) ? "clawix.computerUse" : "clawix.mcp",
                text: text
            ))
        }
        for (idx, name) in dynamicTools.enumerated() {
            rows.append(ToolTimelineRow(
                id: "dyn\(idx)",
                icon: "wrench.and.screwdriver",
                text: L10n.usedTool(name)
            ))
        }
        if imageGenerations > 0 {
            rows.append(ToolTimelineRow(
                id: "imgGen",
                icon: "photo",
                text: L10n.generatedImages(imageGenerations)
            ))
        }
        if imageViews > 0 {
            rows.append(ToolTimelineRow(
                id: "imgView",
                icon: "eye",
                text: L10n.viewedImages(imageViews)
            ))
        }
        return rows
    }

    private static func detailRow(for item: WorkItem, fallbackIndex: Int) -> ToolTimelineDetailRow {
        switch item.kind {
        case .command(let text, _):
            let command = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return ToolTimelineDetailRow(
                id: item.id,
                icon: iconForSingleItem(item) ?? "clawix.terminal",
                text: commandLineText(status: item.status, command: command),
                status: item.status,
                previewImagePath: item.generatedImagePath
            )
        default:
            let row = aggregateRows(for: [item]).first
            return ToolTimelineDetailRow(
                id: item.id.isEmpty ? "item-\(fallbackIndex)" : item.id,
                icon: row?.icon ?? iconForSingleItem(item) ?? "wrench.and.screwdriver",
                text: row?.text ?? fallbackDetailText(for: item),
                status: item.status,
                previewImagePath: item.generatedImagePath
            )
        }
    }

    private static func commandLineText(status: WorkItemStatus, command: String) -> String {
        let prefix: String
        switch status {
        case .inProgress:
            prefix = String(localized: "Running", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .completed:
            prefix = String(localized: "Ran", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .failed:
            prefix = String(localized: "Failed", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        return command.isEmpty ? L10n.ranCommands(1) : "\(prefix) \(command)"
    }

    private static func fallbackDetailText(for item: WorkItem) -> String {
        switch item.kind {
        case .webSearch:
            return L10n.searchedWeb(1)
        case .mcpTool(let server, let tool):
            return L10n.usedTool(prettyMcpServer(mcpServerBucket(server: server, tool: tool)))
        case .dynamicTool(let name):
            return L10n.usedTool(name.isEmpty ? "tool" : name)
        case .imageGeneration:
            return L10n.generatedImages(1)
        case .imageView:
            return L10n.viewedImages(1)
        case .jsCall(_, .browser):
            return String(localized: "Used the browser", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .jsCall(_, .repl), .jsReset:
            return L10n.usedTool("Node Repl")
        case .fileChange(let paths):
            let count = max(1, Set(paths.filter { !$0.isEmpty }).count)
            return L10n.editedFiles(count)
        case .command:
            return L10n.ranCommands(1)
        }
    }

    private static func iconForSingleItem(_ item: WorkItem) -> String? {
        switch item.kind {
        case .command(_, let actions):
            if actions.contains(.listFiles) { return "clawix.folderStack" }
            if actions.contains(.read) || actions.contains(.search) { return "magnifyingglass" }
            return "clawix.terminal"
        case .fileChange:
            return "clawix.pencil"
        case .webSearch:
            return "clawix.globe"
        case .mcpTool(let server, let tool):
            return isComputerUseMcpServer(mcpServerBucket(server: server, tool: tool))
                ? "clawix.computerUse"
                : "clawix.mcp"
        case .dynamicTool(let name):
            let lower = name.lowercased()
            if lower.contains("browser") { return "clawix.cursor" }
            if lower.contains("web") { return "clawix.globe" }
            return "wrench.and.screwdriver"
        case .imageGeneration:
            return "photo"
        case .imageView:
            return "eye"
        case .jsCall(_, .browser):
            return "clawix.cursor"
        case .jsCall(_, .repl), .jsReset:
            return "command"
        }
    }

    private static func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !value.isEmpty {
            if seen.insert(value).inserted {
                result.append(value)
            }
        }
        return result
    }
}

private final class ToolTimelinePresentationCache {
    static let shared = ToolTimelinePresentationCache()

    private var accumulators: [UUID: Accumulator] = [:]
    private var order: [UUID] = []
    private let limit = 512

    private init() {}

    func snapshot(groupID: UUID, items: [WorkItem]) -> ToolTimelinePresentationSnapshot {
        let accumulator = Accumulator(items: items)
        accumulators[groupID] = accumulator
        remember(groupID)
        PerfSignpost.uiChat.event("tool.snapshot.seed", items.count)
        return accumulator.snapshot()
    }

    func updatedSnapshot(
        groupID: UUID,
        previousItems: [WorkItem],
        currentSnapshot: ToolTimelinePresentationSnapshot?,
        applying item: WorkItem
    ) -> ToolTimelinePresentationSnapshot {
        let accumulator: Accumulator
        if let existing = accumulators[groupID],
           existing.version == currentSnapshot?.version {
            accumulator = existing
            PerfSignpost.uiChat.event("tool.snapshot.delta_hit", previousItems.count)
        } else {
            accumulator = Accumulator(items: previousItems, version: currentSnapshot?.version ?? 0)
            accumulators[groupID] = accumulator
            remember(groupID)
            PerfSignpost.uiChat.event("tool.snapshot.delta_seed", previousItems.count)
        }
        accumulator.upsert(item)
        return accumulator.snapshot()
    }

    private func remember(_ groupID: UUID) {
        if !order.contains(groupID) {
            order.append(groupID)
        }
        guard order.count > limit else { return }
        let overflow = order.count - limit
        for oldID in order.prefix(overflow) {
            accumulators.removeValue(forKey: oldID)
        }
        order.removeFirst(overflow)
    }

    private final class Accumulator {
        private(set) var version = 0

        private var itemOrder: [String] = []
        private var contributionsByID: [String: Contribution] = [:]

        private var readFiles = 0
        private var listed = 0
        private var searchedItems = 0
        private var ranCommands = 0
        private var fileChanges = 0
        private var dynamicBrowserIDs: Set<String> = []
        private var webSearchCount = 0
        private var mcpServerOrder: [String] = []
        private var mcpServerCounts: [String: Int] = [:]
        private var imageGenerations = 0
        private var imageViews = 0
        private var jsBrowserCount = 0
        private var jsReplCount = 0

        init(items: [WorkItem], version: Int = 0) {
            self.version = version
            for item in items {
                apply(item)
            }
        }

        func upsert(_ item: WorkItem) {
            if let old = contributionsByID[item.id] {
                remove(old)
            }
            apply(item)
            version += 1
        }

        func snapshot() -> ToolTimelinePresentationSnapshot {
            let aggregateRows = buildRows()
            let runningCommands = itemOrder.compactMap { id -> WorkItem? in
                guard let contribution = contributionsByID[id],
                      contribution.runningCommandText != nil
                else { return nil }
                return contribution.item
            }
            let runningText = runningCommands.compactMap { item -> String? in
                guard case .command(let text, _) = item.kind, let text, !text.isEmpty else {
                    return nil
                }
                return text
            }
            let accessibilityLabel = AccessibilityText.clipped(
                (aggregateRows.map(\.text) + runningText).joined(separator: ". ")
            )
            return ToolTimelinePresentationSnapshot(
                version: version,
                aggregateRows: aggregateRows,
                runningCommands: runningCommands,
                accessibilityLabel: accessibilityLabel
            )
        }

        private func apply(_ item: WorkItem) {
            if contributionsByID[item.id] == nil {
                itemOrder.append(item.id)
            }
            let contribution = Contribution(item: item)
            contributionsByID[item.id] = contribution
            add(contribution)
        }

        private func add(_ contribution: Contribution) {
            readFiles += contribution.readFiles
            listed += contribution.listed
            searchedItems += contribution.searchedItems
            ranCommands += contribution.ranCommands
            fileChanges += contribution.fileChanges
            webSearchCount += contribution.webSearchCount
            imageGenerations += contribution.imageGenerations
            imageViews += contribution.imageViews
            jsBrowserCount += contribution.jsBrowserCount
            jsReplCount += contribution.jsReplCount
            if contribution.dynamicBrowserUsed {
                dynamicBrowserIDs.insert(contribution.item.id)
            }
            if let server = contribution.mcpServer, !server.isEmpty {
                if mcpServerCounts[server] == nil {
                    mcpServerOrder.append(server)
                }
                mcpServerCounts[server, default: 0] += 1
            }
        }

        private func remove(_ contribution: Contribution) {
            readFiles -= contribution.readFiles
            listed -= contribution.listed
            searchedItems -= contribution.searchedItems
            ranCommands -= contribution.ranCommands
            fileChanges -= contribution.fileChanges
            webSearchCount -= contribution.webSearchCount
            imageGenerations -= contribution.imageGenerations
            imageViews -= contribution.imageViews
            jsBrowserCount -= contribution.jsBrowserCount
            jsReplCount -= contribution.jsReplCount
            if contribution.dynamicBrowserUsed {
                dynamicBrowserIDs.remove(contribution.item.id)
            }
            if let server = contribution.mcpServer, !server.isEmpty {
                let next = max(0, (mcpServerCounts[server] ?? 0) - 1)
                if next == 0 {
                    mcpServerCounts.removeValue(forKey: server)
                    mcpServerOrder.removeAll { $0 == server }
                } else {
                    mcpServerCounts[server] = next
                }
            }
        }

        private func buildRows() -> [ToolTimelineRow] {
            var rows: [ToolTimelineRow] = []

            let hasPrimaryWork = fileChanges > 0 || readFiles > 0 || listed > 0 || searchedItems > 0 || ranCommands > 0
            let totalBrowser = jsBrowserCount + (dynamicBrowserIDs.isEmpty ? 0 : 1)
            let inlineMcpServers = hasPrimaryWork ? Set(mcpServerOrder) : []

            if hasPrimaryWork {
                var parts: [String] = []
                if fileChanges > 0 { parts.append(L10n.editedFiles(fileChanges)) }
                if readFiles > 0 {
                    parts.append(parts.isEmpty
                        ? L10n.exploredFiles(readFiles)
                        : L10n.exploredFilesInline(readFiles))
                }
                if searchedItems > 0 {
                    parts.append(parts.isEmpty
                        ? L10n.exploredSearches(searchedItems)
                        : L10n.searchedItems(searchedItems))
                }
                if listed > 0 {
                    parts.append(parts.isEmpty
                        ? L10n.listedItems(listed)
                        : L10n.listedItemsInline(listed))
                }
                if ranCommands > 0 {
                    parts.append(parts.isEmpty
                        ? L10n.ranCommands(ranCommands)
                        : L10n.ranCommandsInline(ranCommands))
                }
                if totalBrowser > 0 {
                    parts.append(String(localized: "used the browser", bundle: AppLocale.bundle, locale: AppLocale.current))
                }
                if webSearchCount > 0 {
                    parts.append(L10n.searchedWebInline(webSearchCount))
                }
                for server in mcpServerOrder {
                    parts.append(L10n.usedToolInline(prettyMcpServer(server)))
                }
                let icon: String
                if fileChanges > 0 {
                    icon = "clawix.pencil"
                } else if listed > 0 {
                    icon = "clawix.folderStack"
                } else if readFiles > 0 || searchedItems > 0 {
                    icon = "magnifyingglass"
                } else {
                    icon = "clawix.terminal"
                }
                rows.append(ToolTimelineRow(
                    id: "exec",
                    icon: icon,
                    text: parts.joined(separator: ", ")
                ))
            }
            if totalBrowser > 0 && !hasPrimaryWork {
                let text: String
                if totalBrowser <= 1 {
                    text = String(localized: "Used the browser", bundle: AppLocale.bundle, locale: AppLocale.current)
                } else {
                    text = L10n.usedToolTimes("the browser", totalBrowser)
                }
                rows.append(ToolTimelineRow(
                    id: "browser",
                    icon: "clawix.cursor",
                    text: text
                ))
            }
            if jsReplCount > 0 {
                let text = jsReplCount <= 1
                    ? L10n.usedTool("Node Repl")
                    : L10n.usedToolTimes("Node Repl", jsReplCount)
                rows.append(ToolTimelineRow(
                    id: "nodeRepl",
                    icon: "command",
                    text: text
                ))
            }
            if webSearchCount > 0 && !hasPrimaryWork {
                let text = L10n.searchedWeb(webSearchCount)
                rows.append(ToolTimelineRow(id: "webSearch", icon: "clawix.globe", text: text))
            }
            for (idx, server) in mcpServerOrder.enumerated() {
                if inlineMcpServers.contains(server) { continue }
                let count = mcpServerCounts[server] ?? 1
                let pretty = prettyMcpServer(server)
                let text = count <= 1 ? L10n.usedTool(pretty) : L10n.usedToolTimes(pretty, count)
                rows.append(ToolTimelineRow(
                    id: "mcp\(idx)",
                    icon: isComputerUseMcpServer(server) ? "clawix.computerUse" : "clawix.mcp",
                    text: text
                ))
            }
            let dynamicTools = itemOrder.compactMap { id in
                contributionsByID[id]?.dynamicToolName
            }
            for (idx, name) in dynamicTools.enumerated() {
                rows.append(ToolTimelineRow(
                    id: "dyn\(idx)",
                    icon: "wrench.and.screwdriver",
                    text: L10n.usedTool(name)
                ))
            }
            if imageGenerations > 0 {
                rows.append(ToolTimelineRow(
                    id: "imgGen",
                    icon: "photo",
                    text: L10n.generatedImages(imageGenerations)
                ))
            }
            if imageViews > 0 {
                rows.append(ToolTimelineRow(
                    id: "imgView",
                    icon: "eye",
                    text: L10n.viewedImages(imageViews)
                ))
            }
            return rows
        }
    }

    private struct Contribution {
        let item: WorkItem
        var readFiles = 0
        var listed = 0
        var searchedItems = 0
        var ranCommands = 0
        var fileChanges = 0
        var dynamicBrowserUsed = false
        var webSearchCount = 0
        var mcpServer: String?
        var dynamicToolName: String?
        var imageGenerations = 0
        var imageViews = 0
        var jsBrowserCount = 0
        var jsReplCount = 0
        var runningCommandText: String?

        init(item: WorkItem) {
            self.item = item
            switch item.kind {
            case .command(let text, let actions):
                if item.status == .inProgress {
                    runningCommandText = text
                    return
                }
                let reads = actions.filter { $0 == .read }.count
                let lists = actions.filter { $0 == .listFiles }.count
                let searches = actions.filter { $0 == .search }.count
                if reads + lists + searches > 0 {
                    readFiles = reads
                    listed = lists
                    searchedItems = searches
                } else {
                    ranCommands = 1
                }
            case .fileChange(let paths):
                fileChanges = max(1, paths.count)
            case .webSearch:
                webSearchCount = 1
            case .mcpTool(let server, let tool):
                mcpServer = mcpServerBucket(server: server, tool: tool)
            case .dynamicTool(let name):
                let lower = name.lowercased()
                if lower.contains("browser") {
                    dynamicBrowserUsed = true
                } else if lower.contains("web") {
                    webSearchCount = 1
                } else {
                    dynamicToolName = name
                }
            case .imageGeneration:
                imageGenerations = 1
            case .imageView:
                imageViews = 1
            case .jsCall(_, .browser):
                jsBrowserCount = 1
            case .jsCall(_, .repl):
                jsReplCount = 1
            case .jsReset:
                jsReplCount = 1
            }
        }
    }
}
