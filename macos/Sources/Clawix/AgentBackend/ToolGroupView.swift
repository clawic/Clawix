import SwiftUI

// Inline tool-group row that appears between reasoning chunks in an
// assistant message timeline. The visible row uses the compact activity
// summary generated from the full group, matching the upstream work
// transcript while keeping raw work items available for accessibility
// and previews.

struct ToolGroupView: View {
    let items: [WorkItem]
    private let snapshot: ToolTimelinePresentationSnapshot
    @State private var expandedRows: Set<String> = []

    init(items: [WorkItem], presentation: ToolTimelinePresentationSnapshot? = nil) {
        self.items = items
        self.snapshot = presentation ?? ToolTimelinePresentation.snapshot(for: items)
    }

    var body: some View {
        let _ = markBodyEvaluation()
        VStack(alignment: .leading, spacing: 14) {
            ForEach(aggregateRows) { row in
                let details = completedDetailRows(for: row)
                VStack(alignment: .leading, spacing: 8) {
                    aggregateRow(row, hasDetails: !details.isEmpty)
                    if expandedRows.contains(row.id) {
                        ForEach(details) { detail in
                            completedDetailRow(detail)
                        }
                    }
                }
            }
            ForEach(previewImageRows) { row in
                if let path = row.previewImagePath, !path.isEmpty {
                    ToolImagePreview(path: path)
                        .padding(.leading, aggregateRows.isEmpty ? 0 : 24)
                }
            }
            ForEach(runningRows) { row in
                detailRow(row)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
        .onAppear {
            markAppeared()
        }
    }

    private func markBodyEvaluation() {
        RenderProbe.tick("ToolGroupView")
        RenderProbe.count("ToolGroupVisibleItems", by: items.count, recordsActivity: false)
        RenderProbe.count("ToolGroupVisibleAggregateRows", by: snapshot.aggregateRows.count, recordsActivity: false)
        RenderProbe.count("ToolGroupVisibleDetailRows", by: runningRows.count, recordsActivity: false)
        RenderProbe.count("ToolGroupVisibleRunningRows", by: runningRows.count, recordsActivity: false)
    }

    private func markAppeared() {
        RenderProbe.markPassive(
            "ToolGroupAppeared",
            fields: [
                "aggregateRows": "\(snapshot.aggregateRows.count)",
                "items": "\(items.count)",
                "runningRows": "\(snapshot.runningCommands.count)"
            ]
        )
    }

    // MARK: - Detail rows

    private var detailRows: [ToolTimelineDetailRow] {
        ToolTimelinePresentation.detailRows(for: items)
    }

    private var previewImageRows: [ToolTimelineDetailRow] {
        ToolTimelinePresentation.previewImageRows(for: items)
    }

    private var runningRows: [ToolTimelineDetailRow] {
        detailRows.filter { $0.status == .inProgress }
    }

    @ViewBuilder
    private func detailRow(_ row: ToolTimelineDetailRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                icon(row.icon)
                    .foregroundColor(iconColor(for: row.status))
                    .frame(width: 16, alignment: .leading)
                if row.status == .inProgress {
                    ShimmerText(
                        text: row.text,
                        font: BodyFont.system(size: 13, wght: 500),
                        color: .white,
                        baseOpacity: 0.30,
                        peakOpacity: 0.80,
                        cycleDuration: 3.0,
                        radius: 6.0
                    )
                } else {
                    Text(verbatim: row.text)
                        .font(BodyFont.system(size: 13, wght: 500))
                        .foregroundColor(textColor(for: row.status))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let path = row.previewImagePath, !path.isEmpty {
                ToolImagePreview(path: path)
                    .padding(.leading, 24)
            }
        }
    }

    // MARK: - Aggregated rows

    private var aggregateRows: [ToolTimelineRow] {
        snapshot.aggregateRows
    }

    private func completedDetailRows(for row: ToolTimelineRow) -> [ToolTimelineDetailRow] {
        ToolTimelinePresentation.detailRows(for: items, aggregateRowID: row.id)
            .filter { $0.status != .inProgress && !($0.previewImagePath?.isEmpty == false) }
    }

    private func aggregateRow(_ row: ToolTimelineRow, hasDetails: Bool) -> some View {
        Button {
            toggleRow(row.id, hasDetails: hasDetails)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                icon(row.icon)
                    .foregroundColor(Color.gray(light: 0.50, dark: 0.45))
                    .frame(width: 16, alignment: .leading)
                Text(verbatim: row.text)
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color.gray(light: 0.45, dark: 0.55))
                    .fixedSize(horizontal: false, vertical: true)
                if hasDetails {
                    LucideIcon(expandedRows.contains(row.id) ? .chevronDown : .chevronRight, size: 12)
                        .foregroundColor(Color.gray(light: 0.45, dark: 0.55))
                        .offset(y: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasDetails)
        .accessibilityLabel(Text(verbatim: row.text))
        .clxControl("chat.toolRow.\(row.id)", role: "button", label: row.text) {
            toggleRow(row.id, hasDetails: hasDetails)
        }
    }

    private func completedDetailRow(_ row: ToolTimelineDetailRow) -> some View {
        Text(verbatim: row.text)
            .font(BodyFont.system(size: 13, wght: 500))
            .foregroundColor(textColor(for: row.status))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 24)
    }

    private func toggleRow(_ id: String, hasDetails: Bool) {
        guard hasDetails else { return }
        if expandedRows.contains(id) {
            expandedRows.remove(id)
        } else {
            expandedRows.insert(id)
        }
    }

    @ViewBuilder
    private func icon(_ name: String) -> some View {
        switch name {
        case "clawix.terminal":
            TerminalIcon(size: 14)
        case "clawix.globe":
            GlobeIcon(size: 13)
        case "clawix.cursor":
            CursorIcon(size: 13)
        case "clawix.mcp":
            McpIcon(size: 14)
        case "clawix.computerUse":
            LucideIcon(.appWindow, size: 13)
        case "clawix.package":
            LucideIcon(.package, size: 13)
        case "clawix.pencil":
            PencilIconView(color: Color.gray(light: 0.50, dark: 0.45), lineWidth: 1.0)
                .frame(width: 15, height: 15)
                .offset(y: 2)
        case "magnifyingglass":
            SearchIcon(size: 11.5)
        case "eye":
            EyeIcon(size: 16)
        case "clawix.folderStack":
            FolderStackIcon(size: 17)
                .offset(y: 3.5)
        case "command":
            Image(systemName: "command")
                .font(.system(size: 13, weight: .medium))
        default:
            LucideIcon.auto(name, size: 12)
        }
    }

    private func iconColor(for status: WorkItemStatus) -> Color {
        status == .failed ? Palette.danger : Color.gray(light: 0.50, dark: 0.45)
    }

    private func textColor(for status: WorkItemStatus) -> Color {
        status == .failed ? Palette.danger : Color.gray(light: 0.45, dark: 0.55)
    }

    private var accessibilityLabel: String {
        let texts = aggregateRows.map(\.text) + runningRows.map(\.text)
        return AccessibilityText.clipped(texts.joined(separator: ". "))
    }
}

private struct ToolImagePreview: View {
    let path: String
    @State private var image: NSImage?

    private let width: CGFloat = 260
    private let height: CGFloat = 146
    private let radius: CGFloat = 8

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.overlay(0.05)
                LucideIcon(.image, size: 14)
                    .foregroundColor(Color.gray(light: 0.50, dark: 0.45))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.overlay(0.08), lineWidth: 0.6)
        )
        .help(URL(fileURLWithPath: path).lastPathComponent)
        .task(id: path) {
            let source = UserBubbleContent.ImageSource.file(URL(fileURLWithPath: path))
            if let cached = UserImageThumbnailLoader.shared.cachedImage(for: source, maxPixelSize: 640) {
                image = cached
                return
            }
            image = nil
            let loaded = await UserImageThumbnailLoader.shared.thumbnail(for: source, maxPixelSize: 640)
            guard !Task.isCancelled else { return }
            image = loaded.image
        }
    }
}
