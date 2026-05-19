import AppKit
import Combine
import Foundation

/// Single source of truth for EditorDocuments. Persists every document
/// in its own directory under `~/.claw/design/documents/<id>/`
/// with `document.json` plus loose asset files (`logo.png`, `hero.jpg`,
/// `<slot>.png`, ...). Lives next to `DesignStore` but stays separate
/// so opening / saving an instance never touches the Style or
/// Template manifests.
@MainActor
final class EditorStore: ObservableObject {
    typealias LoadOperation = @MainActor (_ rootURL: URL, _ manifestName: String) async throws -> EditorSnapshot

    struct EditorSnapshot: Sendable {
        let documents: [EditorDocument]
    }

    static let shared = EditorStore()

    @Published private(set) var documents: [EditorDocument] = []
    @Published private(set) var isLoading = false

    private let rootURL: URL
    private let fileManager: FileManager
    private let manifestName = "document.json"
    private let loadOperation: LoadOperation
    private var reloadTask: Task<Void, Never>?
    private var reloadGeneration = 0

    init(
        rootURL: URL? = nil,
        fileManager: FileManager = .default,
        autoLoad: Bool = true,
        loadOperation: LoadOperation? = nil
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? EditorStore.defaultRootURL(fileManager: fileManager)
        self.loadOperation = loadOperation ?? { rootURL, manifestName in
            try await EditorStore.loadSnapshot(rootURL: rootURL, manifestName: manifestName)
        }
        ensureRootExists()
        if autoLoad {
            reloadFromDisk()
        }
    }

    deinit {
        reloadTask?.cancel()
    }

    static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        ClawixPersistentSurfacePaths.frameworkGlobalChild("design", isDirectory: true)
            .appendingPathComponent("documents", isDirectory: true)
    }

    func documentDir(for id: String) -> URL { rootURL.appendingPathComponent(id) }
    func documentManifestURL(for id: String) -> URL { documentDir(for: id).appendingPathComponent(manifestName) }
    func document(id: String) -> EditorDocument? { documents.first(where: { $0.id == id }) }

    func reloadFromDisk() {
        ensureRootExists()
        _ = startReload()
    }

    func refresh() async {
        await startReload().value
    }

    func cancelSurfaceWork() {
        reloadGeneration += 1
        reloadTask?.cancel()
        reloadTask = nil
        isLoading = false
    }

    @discardableResult
    private func startReload() -> Task<Void, Never> {
        reloadGeneration += 1
        let generation = reloadGeneration
        reloadTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runReload(generation: generation)
        }
        reloadTask = task
        return task
    }

    private func runReload(generation: Int) async {
        guard generation == reloadGeneration else { return }
        isLoading = true
        do {
            let snapshot = try await loadOperation(rootURL, manifestName)
            try Task.checkCancellation()
            guard generation == reloadGeneration else { return }
            apply(snapshot)
            finishReloadIfCurrent(generation)
        } catch is CancellationError {
            finishReloadIfCurrent(generation)
        } catch {
            guard generation == reloadGeneration else { return }
            apply(EditorSnapshot(documents: []))
            finishReloadIfCurrent(generation)
        }
    }

    private func finishReloadIfCurrent(_ generation: Int) {
        guard generation == reloadGeneration else { return }
        isLoading = false
        reloadTask = nil
    }

    private func apply(_ snapshot: EditorSnapshot) {
        documents = snapshot.documents.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func create(name: String, template: TemplateManifest, styleId: String, variantId: String?) throws -> EditorDocument {
        let id = generateId(from: name)
        let now = isoNow()
        let document = EditorDocument(
            id: id,
            name: name,
            templateId: template.id,
            styleId: styleId,
            variantId: variantId ?? template.variants.first?.id,
            data: seededSlotValues(for: template),
            createdAt: now,
            updatedAt: now
        )
        try persist(document)
        upsertInMemory(document)
        reloadFromDisk()
        return document
    }

    func update(_ document: EditorDocument) throws {
        var updated = document
        updated.updatedAt = isoNow()
        try persist(updated)
        if let index = documents.firstIndex(where: { $0.id == document.id }) {
            documents[index] = updated
        } else {
            documents.append(updated)
        }
        documents.sort { $0.updatedAt > $1.updatedAt }
    }

    func delete(_ document: EditorDocument) throws {
        let dir = documentDir(for: document.id)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
        documents.removeAll { $0.id == document.id }
        reloadFromDisk()
    }

    func storeAsset(sourceURL: URL, into document: EditorDocument, slotId: String) throws -> SlotAssetValue {
        let dir = documentDir(for: document.id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = sourceURL.pathExtension.lowercased()
        let filename = "\(slotId).\(ext.isEmpty ? "asset" : ext)"
        let dest = dir.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: dest.path) {
            try? fileManager.removeItem(at: dest)
        }
        try fileManager.copyItem(at: sourceURL, to: dest)
        var width: Double?
        var height: Double?
        if let image = NSImage(contentsOf: dest) {
            width = Double(image.size.width)
            height = Double(image.size.height)
        }
        return SlotAssetValue(filename: filename, width: width, height: height)
    }

    func assetURL(for document: EditorDocument, value: SlotAssetValue) -> URL {
        documentDir(for: document.id).appendingPathComponent(value.filename)
    }

    private func persist(_ document: EditorDocument) throws {
        let dir = documentDir(for: document.id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        try data.write(to: documentManifestURL(for: document.id), options: .atomic)
    }

    private func upsertInMemory(_ document: EditorDocument) {
        if let index = documents.firstIndex(where: { $0.id == document.id }) {
            documents[index] = document
        } else {
            documents.append(document)
        }
        documents.sort { $0.updatedAt > $1.updatedAt }
    }

    private func seededSlotValues(for template: TemplateManifest) -> [String: SlotValue] {
        var out: [String: SlotValue] = [:]
        for slot in template.slots {
            switch slot.kind {
            case .list:
                let n = max(2, min(slot.maxItems ?? 3, 3))
                out[slot.id] = .items((1...n).map { "Item \($0)" })
            case .image, .logo:
                out[slot.id] = .empty
            case .divider, .shape:
                out[slot.id] = .empty
            case .heading, .subheading, .body, .quote, .metric, .button, .table:
                out[slot.id] = .text(seedText(for: slot))
            }
        }
        return out
    }

    private func seedText(for slot: TemplateSlot) -> String {
        switch slot.kind {
        case .heading:    return slot.placeholder ?? slot.label
        case .subheading: return slot.placeholder ?? slot.label
        case .body:       return slot.placeholder ?? "Body copy. Edit to match the story you want this piece to tell."
        case .quote:      return slot.placeholder ?? "Pick a line that earns the whole canvas."
        case .metric:     return slot.placeholder ?? "0"
        case .button:     return slot.placeholder ?? slot.label
        case .table:      return slot.placeholder ?? "Column A | Column B"
        default:          return slot.placeholder ?? slot.label
        }
    }

    private func ensureRootExists() {
        if !fileManager.fileExists(atPath: rootURL.path) {
            try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
    }

    private func generateId(from name: String) -> String {
        let slug = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .prefix(40)
        let suffix = String(UUID().uuidString.split(separator: "-").first ?? "0000").lowercased().prefix(4)
        return "\(slug.isEmpty ? "doc" : String(slug))-\(suffix)"
    }

    private func isoNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func loadSnapshot(rootURL: URL, manifestName: String) async throws -> EditorSnapshot {
        try await Task.detached(priority: .utility) {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return EditorSnapshot(documents: [])
            }

            var found: [EditorDocument] = []
            let decoder = JSONDecoder()
            for entry in entries {
                try Task.checkCancellation()
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else { continue }
                let manifestURL = entry.appendingPathComponent(manifestName)
                guard FileManager.default.fileExists(atPath: manifestURL.path) else { continue }
                do {
                    let data = try Data(contentsOf: manifestURL)
                    let document = try decoder.decode(EditorDocument.self, from: data)
                    found.append(document)
                } catch {
                    // A malformed editor document should not prevent the
                    // rest of the editor library from loading.
                    continue
                }
            }
            return EditorSnapshot(documents: found)
        }.value
    }
}
