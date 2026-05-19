import AppKit
import Combine
import Foundation

/// Single source of truth for the design system surfaced by Clawix:
/// Styles, Templates and References. Each resource lives as its own
/// framework-owned directory under `~/.claw/design/` so
/// the agent (which can be any process writing files there) and the
/// GUI share a contract: write a `STYLE.md` / `TEMPLATE.md` /
/// `REFERENCE.md` and the sidebar picks it up.
///
/// File layout:
/// ```
/// Design/
///   styles/<id>/STYLE.md
///   templates/<id>/TEMPLATE.md
///   references/<id>/REFERENCE.md
/// ```
@MainActor
final class DesignStore: ObservableObject {
    typealias LoadOperation = @MainActor (_ rootURL: URL) async throws -> DesignSnapshot

    struct DesignSnapshot: Sendable {
        let styles: [StyleManifest]
        let templates: [TemplateManifest]
        let references: [ReferenceManifest]
    }

    static let shared = DesignStore()

    @Published private(set) var styles: [StyleManifest] = []
    @Published private(set) var templates: [TemplateManifest] = []
    @Published private(set) var references: [ReferenceManifest] = []
    @Published private(set) var isLoading = false

    private let rootURL: URL
    private let fileManager: FileManager
    private let loadOperation: LoadOperation
    private var pollingTimer: Timer?
    private var reloadTask: Task<Void, Never>?
    private var reloadGeneration = 0

    init(
        rootURL: URL? = nil,
        fileManager: FileManager = .default,
        autoLoad: Bool = true,
        startPolling: Bool = true,
        loadOperation: LoadOperation? = nil
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? DesignStore.defaultRootURL(fileManager: fileManager)
        self.loadOperation = loadOperation ?? { rootURL in
            try await DesignStore.loadSnapshot(rootURL: rootURL)
        }
        ensureLayoutExists()
        seedBuiltinsIfNeeded()
        if autoLoad {
            reloadFromDisk()
        }
        if startPolling {
            startPollingTimer()
        }
    }

    deinit {
        pollingTimer?.invalidate()
        reloadTask?.cancel()
    }

    static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        ClawixPersistentSurfacePaths.frameworkGlobalChild("design", isDirectory: true)
    }

    var stylesRootURL: URL { rootURL.appendingPathComponent("styles") }
    var templatesRootURL: URL { rootURL.appendingPathComponent("templates") }
    var referencesRootURL: URL { rootURL.appendingPathComponent("references") }

    func styleDir(for id: String) -> URL { stylesRootURL.appendingPathComponent(id) }
    func referenceDir(for id: String) -> URL { referencesRootURL.appendingPathComponent(id) }

    // MARK: - Public lookups

    func style(id: String) -> StyleManifest? {
        styles.first(where: { $0.id == id })
    }

    func template(id: String) -> TemplateManifest? {
        templates.first(where: { $0.id == id })
    }

    func reference(id: String) -> ReferenceManifest? {
        references.first(where: { $0.id == id })
    }

    func templatesByCategory() -> [(TemplateCategory, [TemplateManifest])] {
        var bucket: [TemplateCategory: [TemplateManifest]] = [:]
        for template in templates {
            bucket[template.category, default: []].append(template)
        }
        return TemplateCategory.allCases
            .compactMap { category -> (TemplateCategory, [TemplateManifest])? in
                guard let list = bucket[category], !list.isEmpty else { return nil }
                return (category, list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
            }
    }

    // MARK: - Refresh

    func reloadFromDisk() {
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
            let snapshot = try await loadOperation(rootURL)
            try Task.checkCancellation()
            guard generation == reloadGeneration else { return }
            styles = snapshot.styles
            templates = snapshot.templates
            references = snapshot.references
            finishReloadIfCurrent(generation)
        } catch is CancellationError {
            finishReloadIfCurrent(generation)
        } catch {
            finishReloadIfCurrent(generation)
        }
    }

    private func finishReloadIfCurrent(_ generation: Int) {
        guard generation == reloadGeneration else { return }
        isLoading = false
        reloadTask = nil
    }

    // MARK: - Internals

    private func ensureLayoutExists() {
        for dir in [stylesRootURL, templatesRootURL, referencesRootURL] {
            if !fileManager.fileExists(atPath: dir.path) {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    private func seedBuiltinsIfNeeded() {
        if (try? fileManager.contentsOfDirectory(atPath: stylesRootURL.path))?.isEmpty == true {
            for manifest in DesignBuiltins.styles() {
                try? writeStyle(manifest)
            }
        }
        if (try? fileManager.contentsOfDirectory(atPath: templatesRootURL.path))?.isEmpty == true {
            for manifest in DesignBuiltins.templates() {
                try? writeTemplate(manifest)
            }
        }
    }

    // MARK: - Public mutations

    /// Persist edits made to an existing Style. Refuses to overwrite a
    /// builtin manifest unless `forceBuiltin: true` is passed, so
    /// accidental edits to ship-with-Clawix styles surface a clear
    /// error to the caller. Updates `updatedAt` on save.
    func updateStyle(_ manifest: StyleManifest, forceBuiltin: Bool = false) throws {
        if manifest.builtin == true, !forceBuiltin {
            throw NSError(domain: "DesignStore", code: 100, userInfo: [
                NSLocalizedDescriptionKey: "Refusing to overwrite builtin style '\(manifest.id)'. Duplicate it first."
            ])
        }
        var updated = manifest
        updated.updatedAt = isoNow()
        try writeStyle(updated)
        reloadFromDisk()
    }

    /// Create a new Style by duplicating an existing one (typically a
    /// builtin the user wants to tweak). Returns the new id.
    @discardableResult
    func duplicateStyle(_ source: StyleManifest, newName: String? = nil) throws -> String {
        let now = isoNow()
        let proposedName = newName ?? "\(source.name) Copy"
        let baseId = source.id.appending("-copy")
        var newId = baseId
        var counter = 2
        while style(id: newId) != nil {
            newId = "\(baseId)-\(counter)"
            counter += 1
        }
        let copy = StyleManifest(
            schemaVersion: source.schemaVersion,
            id: newId,
            name: proposedName,
            description: source.description,
            tags: source.tags,
            tokens: source.tokens,
            brand: source.brand,
            imagery: source.imagery,
            overrides: source.overrides,
            references: [],
            examples: [],
            createdAt: now,
            updatedAt: now,
            builtin: false
        )
        try writeStyle(copy)
        reloadFromDisk()
        return newId
    }

    /// Delete a non-builtin style from disk. Builtins are protected.
    func deleteStyle(_ manifest: StyleManifest) throws {
        guard manifest.builtin != true else {
            throw NSError(domain: "DesignStore", code: 101, userInfo: [
                NSLocalizedDescriptionKey: "Builtin styles cannot be deleted."
            ])
        }
        let dir = styleDir(for: manifest.id)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
        reloadFromDisk()
    }

    /// Persist a freshly-built reference (already populated from a
    /// drop, URL or file picker).
    @discardableResult
    func addReference(_ manifest: ReferenceManifest, assetSource: URL? = nil) throws -> ReferenceManifest {
        let dir = referenceDir(for: manifest.id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        var stored = manifest
        if let assetSource {
            let filename = assetSource.lastPathComponent
            let dest = dir.appendingPathComponent(filename)
            if !fileManager.fileExists(atPath: dest.path) {
                try fileManager.copyItem(at: assetSource, to: dest)
            }
            stored.asset = filename
        }
        stored.updatedAt = isoNow()
        try writeReference(stored)
        reloadFromDisk()
        return stored
    }

    /// Remove a reference and its asset folder.
    func deleteReference(_ manifest: ReferenceManifest) throws {
        let dir = referenceDir(for: manifest.id)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
        // Drop any style ↦ reference link so nothing dangles.
        for style in styles where style.references?.contains(manifest.id) == true {
            var updated = style
            updated.references = updated.references?.filter { $0 != manifest.id }
            updated.updatedAt = isoNow()
            try? writeStyle(updated)
        }
        reloadFromDisk()
    }

    /// Toggle a `referenceId` on a `styleId`. Adds if absent, removes
    /// if present. Mirrors the link on both sides.
    func toggleReferenceLink(referenceId: String, styleId: String) throws {
        guard var style = style(id: styleId) else {
            throw NSError(domain: "DesignStore", code: 102, userInfo: [
                NSLocalizedDescriptionKey: "Style '\(styleId)' not found."
            ])
        }
        guard var ref = reference(id: referenceId) else {
            throw NSError(domain: "DesignStore", code: 103, userInfo: [
                NSLocalizedDescriptionKey: "Reference '\(referenceId)' not found."
            ])
        }
        var styleRefs = Set(style.references ?? [])
        var refStyles = Set(ref.styleIds ?? [])
        if styleRefs.contains(referenceId) {
            styleRefs.remove(referenceId)
            refStyles.remove(styleId)
        } else {
            styleRefs.insert(referenceId)
            refStyles.insert(styleId)
        }
        style.references = Array(styleRefs).sorted()
        style.updatedAt = isoNow()
        ref.styleIds = Array(refStyles).sorted()
        ref.updatedAt = isoNow()
        try writeStyle(style)
        try writeReference(ref)
        reloadFromDisk()
    }

    /// Internal: build a fresh ISO-8601 timestamp.
    private func isoNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private func writeReference(_ manifest: ReferenceManifest) throws {
        let dir = referenceDir(for: manifest.id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload = try DesignSerializer.writeReference(manifest)
        try payload.data(using: .utf8)?.write(to: dir.appendingPathComponent("REFERENCE.md"), options: .atomic)
    }

    private func writeStyle(_ manifest: StyleManifest) throws {
        let dir = stylesRootURL.appendingPathComponent(manifest.id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload = try DesignSerializer.writeStyle(manifest)
        try payload.data(using: .utf8)?.write(to: dir.appendingPathComponent("STYLE.md"), options: .atomic)
    }

    private func writeTemplate(_ manifest: TemplateManifest) throws {
        let dir = templatesRootURL.appendingPathComponent(manifest.id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload = try DesignSerializer.writeTemplate(manifest)
        try payload.data(using: .utf8)?.write(to: dir.appendingPathComponent("TEMPLATE.md"), options: .atomic)
    }

    private func startPollingTimer() {
        let timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reloadFromDisk()
            }
        }
        timer.tolerance = 1.0
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer
    }

    private static func loadSnapshot(rootURL: URL) async throws -> DesignSnapshot {
        try await Task.detached(priority: .utility) {
            let stylesRootURL = rootURL.appendingPathComponent("styles")
            let templatesRootURL = rootURL.appendingPathComponent("templates")
            let referencesRootURL = rootURL.appendingPathComponent("references")
            let styles = readAllStyles(from: stylesRootURL)
            try Task.checkCancellation()
            let templates = readAllTemplates(from: templatesRootURL)
            try Task.checkCancellation()
            let references = readAllReferences(from: referencesRootURL)
            try Task.checkCancellation()
            return DesignSnapshot(styles: styles, templates: templates, references: references)
        }.value
    }

    private nonisolated static func readAllStyles(from stylesRootURL: URL) -> [StyleManifest] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: stylesRootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        var out: [StyleManifest] = []
        for entry in entries {
            let manifestPath = entry.appendingPathComponent("STYLE.md")
            guard let content = try? String(contentsOf: manifestPath, encoding: .utf8) else { continue }
            if let manifest = try? DesignSerializer.parseStyle(content) {
                out.append(manifest)
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private nonisolated static func readAllTemplates(from templatesRootURL: URL) -> [TemplateManifest] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: templatesRootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        var out: [TemplateManifest] = []
        for entry in entries {
            let manifestPath = entry.appendingPathComponent("TEMPLATE.md")
            guard let content = try? String(contentsOf: manifestPath, encoding: .utf8) else { continue }
            if let manifest = try? DesignSerializer.parseTemplate(content) {
                out.append(manifest)
            }
        }
        return out
    }

    private nonisolated static func readAllReferences(from referencesRootURL: URL) -> [ReferenceManifest] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: referencesRootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        var out: [ReferenceManifest] = []
        for entry in entries {
            let manifestPath = entry.appendingPathComponent("REFERENCE.md")
            guard let content = try? String(contentsOf: manifestPath, encoding: .utf8) else { continue }
            if let manifest = try? DesignSerializer.parseReference(content) {
                out.append(manifest)
            }
        }
        return out.sorted { $0.updatedAt > $1.updatedAt }
    }
}
