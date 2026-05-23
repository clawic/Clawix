import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Adaptive 3-pane Drive screen: folder breadcrumbs + content grid/list +
/// optional detail pane. Content view chooses grid (Photos-style) when
/// the folder is mostly images, list (Finder-style) otherwise. Decision
/// is per-folder and remembered in `@SceneStorage`.
struct DriveScreen: View {
    @EnvironmentObject private var appState: AppState

    enum Mode: Equatable {
        case admin
        case photos
        case documents
        case recent
        case folder(String)
    }

    @StateObject private var store = DriveStore()
    @State private var selectedItemId: String? = nil
    @State private var isUploadDialogPresented = false
    @State private var duplicatePromptForExisting: ClawJSDriveClient.DriveItem? = nil
    @State private var pendingUploadURL: URL? = nil
    @State private var viewMode: ViewMode = .auto

    let mode: Mode

    enum ViewMode: String, CaseIterable {
        case auto, grid, list
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(Palette.popupStroke)
                .frame(height: 0.5)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
        .onAppear {
            applyMode()
            DriveTools.bind(store)
            presentPendingQuickUploadIfReady()
        }
        .task {
            let lease = await ClawJSServiceManager.shared.acquire(
                services: [.drive],
                reason: .route("drive"),
                consumer: "route.drive"
            )
            defer { Task { await ClawJSServiceManager.shared.release(lease) } }
            store.boot()
            await ClawJSServiceManager.holdDemandUntilCancelled()
        }
        .onDisappear {
            store.cancelSurfaceWork()
        }
        .onChange(of: mode) { _, _ in applyMode() }
        .onChange(of: appState.driveQuickUploadRequestID) { _, _ in
            presentPendingQuickUploadIfReady()
        }
        .onChange(of: store.state) { _, _ in
            presentPendingQuickUploadIfReady()
        }
        .onReceive(NotificationCenter.default.publisher(for: .driveQuickUploadRequested)) { _ in
            if canUpload {
                isUploadDialogPresented = true
            }
        }
        .alert("Already in Drive", isPresented: Binding(
            get: { duplicatePromptForExisting != nil },
            set: { if !$0 { duplicatePromptForExisting = nil } }
        )) {
            Button("Replace") {
                if let url = pendingUploadURL, let existing = duplicatePromptForExisting {
                    Task { @MainActor in
                        await store.replaceDuplicate(
                            existingId: existing.id,
                            fileURL: url,
                            parentId: store.currentParentId
                        )
                        pendingUploadURL = nil
                        duplicatePromptForExisting = nil
                    }
                }
            }
            Button("Keep both") {
                if let url = pendingUploadURL {
                    Task { @MainActor in
                        _ = await store.upload(fileURL: url, parentId: store.currentParentId, allowOverwrite: true)
                        duplicatePromptForExisting = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) { duplicatePromptForExisting = nil }
        } message: {
            if let existing = duplicatePromptForExisting {
                Text("\"\(existing.name)\" with the same content already exists in your Drive.")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(headerTitle)
                .font(BodyFont.system(size: 20, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
            Spacer()
            HStack(spacing: 6) {
                IconImage("magnifyingglass", size: 12)
                    .foregroundColor(Palette.textSecondary)
                TextField("Search", text: Binding(get: { store.query }, set: { store.setQuery($0) }))
                    .textFieldStyle(.plain)
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .frame(maxWidth: 280)
            .background(Capsule(style: .continuous).fill(Color.overlay(0.06)))
            SlidingSegmented(
                selection: $viewMode,
                options: ViewMode.allCases.map { ($0, $0.rawValue.capitalized) },
                height: 28,
                fontSize: 11.5
            )
            .frame(width: 180)
            Button { isUploadDialogPresented = true } label: {
                HStack(spacing: 4) {
                    IconImage("plus", size: 11)
                    Text("Upload")
                }
                .font(BodyFont.system(size: 12, wght: 600))
                .foregroundColor(canUpload ? Palette.background : Color.overlay(0.55))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule(style: .continuous).fill(canUpload ? Color.overlay(0.92) : Color.overlay(0.18)))
            }
            .buttonStyle(.plain)
            .disabled(!canUpload)
        }
        .padding(12)
        .fileImporter(isPresented: $isUploadDialogPresented, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for url in urls {
                    pendingUploadURL = url
                    Task { @MainActor in
                        let result = await store.upload(fileURL: url, parentId: store.currentParentId)
                        if case .failure(let error) = result, case .duplicateExists(let existing) = error {
                            duplicatePromptForExisting = existing
                        } else {
                            pendingUploadURL = nil
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .loading, .authenticating:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting to Drive…")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            DrivePlaceholder(icon: "exclamationmark.triangle",
                             title: "Drive unavailable",
                             message: message)
        case .unauthenticated, .ready:
            HSplitView {
                folderTree
                    .frame(
                        minWidth: 220,
                        idealWidth: 260,
                        maxWidth: 320,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                contentBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if let id = selectedItemId, let item = visibleItems.first(where: { $0.id == id }) {
                    DriveItemDetailPane(item: item, store: store)
                        .frame(
                            minWidth: 280,
                            idealWidth: 320,
                            maxWidth: 420,
                            maxHeight: .infinity,
                            alignment: .topLeading
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var folderTree: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(["my-drive", "recent", "starred", "shared", "trash"], id: \.self) { view in
                DriveSidebarRow(
                    icon: iconFor(view),
                    title: label(for: view),
                    count: count(for: view),
                    isSelected: store.currentView == view,
                    action: { store.setView(view) }
                )
            }
            if !store.breadcrumbs.isEmpty {
                Rectangle()
                    .fill(Palette.popupStroke)
                    .frame(height: 0.5)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                Text("Breadcrumbs")
                    .font(BodyFont.system(size: 11.5, wght: 600))
                    .foregroundColor(Palette.textSecondary)
                    .padding(.horizontal, 11)
                    .padding(.bottom, 4)
                ForEach(store.breadcrumbs, id: \.id) { crumb in
                    Button {
                        store.setParent(crumb.id)
                    } label: {
                        Text(crumb.name)
                            .font(BodyFont.system(size: 12.5, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
    }

    private var contentBody: some View {
        Group {
            if visibleItems.isEmpty {
                DrivePlaceholder(icon: "tray.and.arrow.down",
                                 title: "Nothing here yet",
                                 message: "Drag a file here or click Upload.")
            } else {
                if effectiveLayout == .grid {
                    DriveGridView(items: visibleItems, selectedId: $selectedItemId, store: store)
                } else {
                    DriveListView(items: visibleItems, selectedId: $selectedItemId, store: store)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard canUpload else { return false }
            handleDrop(providers: providers)
            return true
        }
    }

    private var effectiveLayout: ViewMode {
        if viewMode != .auto { return viewMode }
        // Auto: grid when ≥70% of items are images.
        let images = visibleItems.filter { isImage($0) }.count
        return visibleItems.count > 0 && Double(images) / Double(visibleItems.count) >= 0.7 ? .grid : .list
    }

    private var visibleItems: [ClawJSDriveClient.DriveItem] {
        switch mode {
        case .photos:
            return store.items.filter { $0.kind == "folder" || isImage($0) }
        case .documents:
            return store.items.filter { $0.kind == "folder" || !isImage($0) }
        case .admin, .recent, .folder:
            return store.items
        }
    }

    private func isImage(_ item: ClawJSDriveClient.DriveItem) -> Bool {
        (item.mimeType ?? "").starts(with: "image/")
    }

    private var headerTitle: String {
        switch mode {
        case .photos: return "Photos"
        case .documents: return "Documents"
        case .recent: return "Recent"
        case .admin: return "Drive"
        case .folder: return store.breadcrumbs.last?.name ?? "Folder"
        }
    }

    private var canUpload: Bool {
        if case .ready = store.state { return true }
        return false
    }

    private func presentPendingQuickUploadIfReady() {
        guard let requestID = appState.driveQuickUploadRequestID, canUpload else { return }
        isUploadDialogPresented = true
        appState.consumeDriveQuickUploadRequest(requestID)
    }

    private func applyMode() {
        selectedItemId = nil
        switch mode {
        case .photos:
            store.setView("my-drive")
            // Photos timeline filters by mime client-side via grid layout decision.
        case .documents:
            store.setView("my-drive")
        case .recent:
            store.setView("recent")
        case .admin:
            store.setView("my-drive")
            store.setParent(nil)
        case .folder(let id):
            store.setView("my-drive")
            store.setParent(id)
        }
    }

    private func iconFor(_ view: String) -> String {
        switch view {
        case "my-drive": return "internaldrive"
        case "recent": return "clock"
        case "starred": return "star"
        case "shared": return "person.2"
        case "trash": return "trash"
        default: return "folder"
        }
    }

    private func label(for view: String) -> String {
        switch view {
        case "my-drive": return "My Drive"
        case "recent": return "Recent"
        case "starred": return "Starred"
        case "shared": return "Shared"
        case "trash": return "Trash"
        default: return view
        }
    }

    private func count(for view: String) -> Int {
        switch view {
        case "my-drive": return store.counts.myDrive
        case "recent": return store.counts.recent
        case "starred": return store.counts.starred
        case "shared": return store.counts.shared
        case "trash": return store.counts.trash
        default: return 0
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url = url else { return }
                    Task { @MainActor in
                        pendingUploadURL = url
                        let result = await store.upload(fileURL: url, parentId: store.currentParentId)
                        if case .failure(let error) = result, case .duplicateExists(let existing) = error {
                            duplicatePromptForExisting = existing
                        } else {
                            pendingUploadURL = nil
                        }
                    }
                }
            }
        }
    }
}

struct DriveGridView: View {
    let items: [ClawJSDriveClient.DriveItem]
    @Binding var selectedId: String?
    let store: DriveStore
    private static let visibleItemLimit = 200

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items.prefix(Self.visibleItemLimit)) { item in
                    DriveItemTile(item: item, store: store, isSelected: selectedId == item.id)
                        .onTapGesture(count: 2) {
                            if item.kind == "folder" { store.setParent(item.id) }
                        }
                        .onTapGesture { selectedId = item.id }
                }
            }
            .padding(12)
        }
        .thinScrollers()
    }
}

struct DriveListView: View {
    let items: [ClawJSDriveClient.DriveItem]
    @Binding var selectedId: String?
    let store: DriveStore

    var body: some View {
        Table(items, selection: $selectedId) {
            TableColumn("Name") { item in
                HStack(spacing: 8) {
                    IconImage(item.kind == "folder" ? "folder" : "doc.text", size: 13)
                        .foregroundColor(Palette.textSecondary)
                    Text(item.name)
                        .font(BodyFont.system(size: 12.5, wght: 500))
                        .foregroundColor(Palette.textPrimary)
                }
            }
            TableColumn("Modified") { item in
                Text(formatRelative(item.updatedAt))
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
            }
            TableColumn("Size") { item in
                Text(formatSize(item.sizeBytes))
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
            }
        }
        .background(DriveListDoubleClickBridge(items: items, selectedId: selectedId, store: store))
    }

    private func formatRelative(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: iso) else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes == 0 { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

private struct DriveListDoubleClickBridge: NSViewRepresentable {
    let items: [ClawJSDriveClient.DriveItem]
    let selectedId: String?
    let store: DriveStore

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configure(context.coordinator, from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(context.coordinator, from: nsView)
    }

    private func configure(_ coordinator: Coordinator, from view: NSView) {
        coordinator.items = items
        coordinator.selectedId = selectedId
        coordinator.store = store
        DispatchQueue.main.async {
            coordinator.install(from: view)
        }
    }

    final class Coordinator: NSObject {
        var items: [ClawJSDriveClient.DriveItem] = []
        var selectedId: String?
        weak var store: DriveStore?
        private weak var installedTableView: NSTableView?

        func install(from view: NSView) {
            guard installedTableView == nil || installedTableView?.window == nil else { return }
            guard let tableView = findTableView(from: view) else { return }
            tableView.target = self
            tableView.doubleAction = #selector(handleDoubleClick(_:))
            installedTableView = tableView
        }

        @objc private func handleDoubleClick(_ sender: NSTableView) {
            let row = sender.clickedRow
            let item: ClawJSDriveClient.DriveItem?
            if row >= 0, row < items.count {
                item = items[row]
            } else if let selectedId {
                item = items.first { $0.id == selectedId }
            } else {
                item = nil
            }
            guard let item, item.kind == "folder", let store else { return }
            Task { @MainActor in
                store.setParent(item.id)
            }
        }

        private func findTableView(from view: NSView) -> NSTableView? {
            var current: NSView? = view
            while let node = current {
                if let tableView = node as? NSTableView {
                    return tableView
                }
                current = node.superview
            }
            guard let root = view.window?.contentView else { return nil }
            return firstTableView(in: root)
        }

        private func firstTableView(in view: NSView) -> NSTableView? {
            if let tableView = view as? NSTableView {
                return tableView
            }
            for child in view.subviews {
                if let tableView = firstTableView(in: child) {
                    return tableView
                }
            }
            return nil
        }
    }
}

struct DriveItemTile: View {
    let item: ClawJSDriveClient.DriveItem
    let store: DriveStore
    let isSelected: Bool
    @State private var thumbnail: NSImage?
    private static let thumbnailMaxPixelSize = 256

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.cardFill)
                if let img = thumbnail {
                    Image(nsImage: img).resizable().scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                } else {
                    LucideIcon.auto(placeholderIconName, size: 36)
                        .foregroundColor(Palette.textTertiary)
                }
            }
            .frame(height: 110)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? Palette.pastelBlue : Palette.popupStroke,
                                  lineWidth: isSelected ? 2 : 0.5)
            )
            Text(item.name)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(Palette.textSecondary)
        }
        .task(id: item.id) {
            if (item.mimeType ?? "").starts(with: "image/") {
                if let data = await store.thumbnail(for: item.id, size: Self.thumbnailMaxPixelSize),
                   let img = Self.downsampledImage(from: data, maxPixelSize: Self.thumbnailMaxPixelSize) {
                    thumbnail = img
                }
            }
        }
    }

    private static func downsampledImage(from data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private var placeholderIconName: String {
        if item.kind == "folder" {
            return "folder.fill"
        }

        let mimeType = item.mimeType?.lowercased() ?? ""
        if mimeType.starts(with: "image/") {
            return "photo"
        }
        if mimeType == "application/pdf" {
            return "doc.text"
        }
        if mimeType.starts(with: "text/") || mimeType == "application/json" {
            return "doc.text"
        }
        if mimeType.starts(with: "audio/") {
            return "waveform"
        }
        if mimeType.starts(with: "video/") {
            return "play"
        }
        return "doc.text"
    }
}

struct DriveItemDetailPane: View {
    let item: ClawJSDriveClient.DriveItem
    let store: DriveStore
    @State private var exif: ClawJSDriveClient.ExifRecord?
    @State private var shares: ClawJSDriveClient.AllSharesResponse?
    @State private var detailError: String?
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(BodyFont.system(size: 15, wght: 700))
                        .foregroundColor(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.mimeType ?? item.kind)
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                    if item.sizeBytes > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(item.sizeBytes), countStyle: .file))
                            .font(BodyFont.system(size: 11.5, wght: 500))
                            .foregroundColor(Palette.textTertiary)
                    }
                }

                if let exif {
                    CardDivider()
                    VStack(alignment: .leading, spacing: 5) {
                        DriveDetailSectionLabel("EXIF")
                        if let taken = exif.takenAt { DriveDetailField("Taken", taken) }
                        if let cam = exif.cameraModel { DriveDetailField("Camera", cam) }
                        if let lat = exif.latitude, let lon = exif.longitude {
                            DriveDetailField("GPS", String(format: "%.4f, %.4f", lat, lon))
                        }
                        if let w = exif.width, let h = exif.height {
                            DriveDetailField("Dimensions", "\(w)×\(h)")
                        }
                    }
                }

                CardDivider()
                VStack(alignment: .leading, spacing: 8) {
                    DriveDetailSectionLabel("Sharing")
                    if let detailError {
                        Text(detailError)
                            .font(BodyFont.system(size: 11.5, wght: 500))
                            .foregroundColor(Palette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 6) {
                        DrivePillButton(title: "Tailnet") { Task { await createTailnetShare() } }
                        DrivePillButton(title: "Public link") { Task { await createTunnelShare() } }
                        DrivePillButton(title: "Agent token") { Task { await createAgentShare() } }
                    }
                    if let shares {
                        VStack(alignment: .leading, spacing: 3) {
                            if !shares.tailnet.isEmpty { DriveDetailField("Tailnet", "\(shares.tailnet.count)") }
                            if !shares.tunnel.isEmpty { DriveDetailField("Tunnels", "\(shares.tunnel.count)") }
                            if !shares.agent.isEmpty { DriveDetailField("Agents", "\(shares.agent.count)") }
                        }
                    }
                }

                CardDivider()
                HStack(spacing: 6) {
                    if item.trashedAt == nil {
                        DrivePillButton(title: "Trash", role: .destructive) {
                            Task { @MainActor in await store.trash(item.id) }
                        }
                    } else {
                        DrivePillButton(title: "Restore") {
                            Task { @MainActor in await store.restore(item.id) }
                        }
                        DrivePillButton(title: "Delete", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                    DrivePillButton(title: item.starred ? "Unstar" : "Star") {
                        Task { @MainActor in await store.star(item.id, starred: !item.starred) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .thinScrollers()
        .task(id: item.id) {
            await store.markViewed(item.id)
            var detailErrors: [String] = []
            if item.mimeType?.hasPrefix("image/") == true {
                do {
                    self.exif = try await store.client.getExif(item.id)
                } catch {
                    self.exif = nil
                    detailErrors.append("EXIF: \(error.localizedDescription)")
                }
            } else {
                self.exif = nil
            }
            do {
                self.shares = try await store.client.listAllShares(item.id)
            } catch {
                self.shares = nil
                detailErrors.append("Sharing: \(error.localizedDescription)")
            }
            let message = detailErrors.isEmpty ? nil : detailErrors.joined(separator: "\n")
            self.detailError = message
            store.lastError = message
        }
        .alert("Delete item?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                Task { @MainActor in await store.delete(item.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes \"\(item.name)\" from Drive.")
        }
    }

    @MainActor
    private func createTailnetShare() async {
        do {
            _ = try await store.client.createTailnetShare(item.id)
            shares = try await store.client.listAllShares(item.id)
            detailError = nil
            store.lastError = nil
        } catch {
            detailError = error.localizedDescription
            store.lastError = error.localizedDescription
        }
    }

    @MainActor
    private func createTunnelShare() async {
        do {
            _ = try await store.client.createTunnelShare(item.id)
            shares = try await store.client.listAllShares(item.id)
            detailError = nil
            store.lastError = nil
        } catch {
            detailError = error.localizedDescription
            store.lastError = error.localizedDescription
        }
    }

    @MainActor
    private func createAgentShare() async {
        do {
            _ = try await store.client.createAgentShare(
                item.id,
                capabilityKind: "drive.item.read",
                ttlMinutes: 10,
                reason: nil,
                agentName: "agent",
            )
            shares = try await store.client.listAllShares(item.id)
            detailError = nil
            store.lastError = nil
        } catch {
            detailError = error.localizedDescription
            store.lastError = error.localizedDescription
        }
    }
}

// MARK: - Drive chrome primitives (canon-aligned)

/// Source/breadcrumb row in the Drive left pane. Mirrors the sidebar
/// canon: 9-pt continuous corners, soft white hover, brighter selected
/// fill, leading icon + title + trailing count.
private struct DriveSidebarRow: View {
    let icon: String
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                IconImage(icon, size: 13)
                    .foregroundColor(isSelected ? Palette.textPrimary : Palette.textSecondary)
                Text(title)
                    .font(BodyFont.system(size: 12.5, wght: isSelected ? 600 : 500))
                    .foregroundColor(isSelected ? Palette.textPrimary : Palette.textSecondary)
                Spacer(minLength: 6)
                if count > 0 {
                    Text(String(count))
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Palette.textTertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.overlay(0.10)
                          : (hovered ? Color.overlay(0.06) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

/// Centered empty/error placeholder for the Drive panes.
private struct DrivePlaceholder: View {
    let icon: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            IconImage(icon, size: 34)
                .foregroundColor(Palette.textTertiary)
            Text(title)
                .font(BodyFont.system(size: 14, wght: 600))
                .foregroundColor(Palette.textSecondary)
            if let message {
                Text(message)
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

/// Secondary text button (canon recipe 6.6): capsule, soft white fill,
/// hairline stroke, hover lift. `destructive` tints the label red.
private struct DrivePillButton: View {
    enum Role { case normal, destructive }
    let title: String
    var role: Role = .normal
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(BodyFont.system(size: 12, wght: 600))
                .foregroundColor(role == .destructive ? Color.red.opacity(0.9) : Palette.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.overlay(hovered ? 0.14 : 0.08))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.overlay(0.10), lineWidth: 0.5)
                        )
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

/// Small section label inside the Drive detail pane.
private struct DriveDetailSectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(BodyFont.system(size: 12, wght: 600))
            .foregroundColor(Palette.textPrimary)
    }
}

/// Label/value field in the Drive detail pane.
private struct DriveDetailField: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(Palette.textTertiary)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
