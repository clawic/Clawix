import AppKit
import Combine
import CryptoKit
import Foundation

/// Single source of truth for the user's installed Apps. Persists each
/// app as a framework-owned folder under `~/.claw/apps/<slug>/`
/// with a `manifest.json` next to the actual web files (`index.html`,
/// `app.js`, `style.css`, ...). The store watches the parent dir on a
/// timer and reloads the index when the agent writes new files from a
/// different process; this keeps the contract between the agent (which
/// can be any process that writes files there) and the GUI minimal:
/// "write a manifest + files; the sidebar will pick it up".
@MainActor
final class AppsStore: ObservableObject {
    typealias LoadOperation = @MainActor (_ rootURL: URL, _ manifestName: String) async throws -> AppsSnapshot

    struct AppsSnapshot: Sendable {
        let apps: [AppRecord]
        let mtimes: [String: Date]
    }

    static let shared = AppsStore()

    @Published private(set) var apps: [AppRecord] = []
    @Published private(set) var isLoading = false

    /// Effective sort: pinned first, then most-recently-opened, then
    /// most-recently-created. Used by every consumer (sidebar, grid).
    var sortedApps: [AppRecord] {
        apps.sorted(by: AppsStore.compareForSidebar)
    }

    private let rootURL: URL
    private let fileManager: FileManager
    private let manifestName = "manifest.json"
    private let loadOperation: LoadOperation
    private let packageTrustPolicy: AppPackageTrustPolicy
    private var pollingTimer: Timer?
    private var reloadTask: Task<Void, Never>?
    private var reloadGeneration = 0
    /// Last-known mtime per slug; used to detect agent-side file changes
    /// without diffing every file's bytes on each poll.
    private var lastSeenMtime: [String: Date] = [:]

    init(
        rootURL: URL? = nil,
        fileManager: FileManager = .default,
        autoLoad: Bool = true,
        startPolling: Bool = true,
        packageTrustPolicy: AppPackageTrustPolicy? = nil,
        loadOperation: LoadOperation? = nil
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? AppsStore.defaultRootURL(fileManager: fileManager)
        self.packageTrustPolicy = packageTrustPolicy ?? AppPackageTrustPolicy.load(
            from: AppPackageTrustPolicy.defaultURL(forAppsRoot: self.rootURL),
            fileManager: fileManager
        )
        self.loadOperation = loadOperation ?? { rootURL, manifestName in
            try await AppsStore.loadSnapshot(rootURL: rootURL, manifestName: manifestName)
        }
        ensureRootExists()
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

    /// `~/.claw/apps`. Apps are framework resources; Clawix only renders
    /// the human UI and app webview shell.
    static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        ClawixPersistentSurfacePaths.frameworkGlobalChild("apps", isDirectory: true)
    }

    /// Bring `apps` in sync with whatever currently lives on disk. Cheap
    /// enough to call on every poll because we short-circuit per-slug
    /// when the manifest mtime hasn't moved.
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
            apply(AppsSnapshot(apps: [], mtimes: [:]))
            finishReloadIfCurrent(generation)
        }
    }

    private func finishReloadIfCurrent(_ generation: Int) {
        guard generation == reloadGeneration else { return }
        isLoading = false
        reloadTask = nil
    }

    private func apply(_ snapshot: AppsSnapshot) {
        let sortedFound = snapshot.apps.sorted(by: AppsStore.compareForSidebar)
        if sortedFound != apps.sorted(by: AppsStore.compareForSidebar) {
            apps = sortedFound
        }
        lastSeenMtime = snapshot.mtimes
    }

    // MARK: - CRUD

    /// Create a brand-new app folder + manifest. Returns the persisted
    /// record. Throws if the slug already exists or contains characters
    /// that would not survive a URL host (a-z, 0-9, dash).
    @discardableResult
    func create(
        name: String,
        slug: String? = nil,
        description: String = "",
        icon: String = "",
        accentColor: String = "",
        projectId: UUID? = nil,
        tags: [String] = [],
        permissions: AppPermissions = .defaults,
        createdByChatId: UUID? = nil,
        declaredCapabilities: [String] = [],
        originClass: AppOriginClass = .localUserAuthored,
        surfaceKind: AppSurfaceKind = .web,
        routeTarget: String? = nil,
        variant: AppVariantMetadata? = nil,
        protectedRoutePolicy: AppProtectedRoutePolicy = .blocked,
        packageProvenance: AppPackageProvenance? = nil,
        activationReview: AppActivationReview? = nil
    ) throws -> AppRecord {
        let resolvedSlug = try uniqueSlug(preferred: slug, name: name)
        let now = Date()
        let record = AppRecord(
            slug: resolvedSlug,
            name: name,
            description: description,
            icon: icon,
            accentColor: accentColor,
            projectId: projectId,
            tags: tags,
            permissions: permissions,
            pinned: false,
            lastOpenedAt: nil,
            createdAt: now,
            updatedAt: now,
            createdByChatId: createdByChatId,
            declaredCapabilities: declaredCapabilities,
            originClass: originClass,
            surfaceKind: surfaceKind,
            routeTarget: routeTarget,
            variant: variant,
            protectedRoutePolicy: protectedRoutePolicy,
            packageProvenance: packageProvenance,
            activationReview: activationReview
        )
        try writeManifest(record)
        // Seed a placeholder index.html so the user can open the app
        // immediately even before the agent has written anything.
        let appDir = directory(forSlug: record.slug)
        let indexURL = appDir.appendingPathComponent("index.html")
        if !fileManager.fileExists(atPath: indexURL.path) {
            let placeholder = AppsStore.placeholderIndexHTML(name: name)
            try? placeholder.data(using: .utf8)?.write(to: indexURL, options: .atomic)
        }
        upsertInMemory(record)
        reloadFromDisk()
        return record
    }

    /// Persist any AppRecord change (rename, pin, permissions, ...). The
    /// manifest is the truth-of-record on disk; reloadFromDisk is what
    /// surfaces it back into `@Published apps`.
    func update(_ record: AppRecord) throws {
        var updated = record
        updated.updatedAt = Date()
        try writeManifest(updated)
        upsertInMemory(updated)
        reloadFromDisk()
    }

    /// Remove an app entirely (folder + manifest + files). Irreversible
    /// from the GUI; the user gets a confirm sheet on the call site.
    func delete(_ record: AppRecord) throws {
        let dir = directory(forSlug: record.slug)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
        removeInMemory(record)
        reloadFromDisk()
    }

    /// Stamp `lastOpenedAt = now` so the app floats to the top of the
    /// recent ordering. Cheap; the manifest is rewritten in place.
    func markOpened(_ record: AppRecord) {
        var updated = record
        updated.lastOpenedAt = Date()
        try? writeManifest(updated)
        upsertInMemory(updated)
        reloadFromDisk()
    }

    func togglePinned(_ record: AppRecord) {
        var updated = record
        updated.pinned.toggle()
        try? update(updated)
    }

    /// Import an existing code+manifest app folder into the managed Apps
    /// store. Imported and marketplace packages must pass the activation
    /// review gate again inside `AppSurfaceView`, even if the source manifest
    /// carried a stale review receipt.
    @discardableResult
    func importApp(
        from sourceURL: URL,
        originClass: AppOriginClass = .imported,
        trustedSignaturePublicKeys: [String: Curve25519.Signing.PublicKey]? = nil
    ) throws -> AppRecord {
        try AppPackageImportValidator.validateSourceDirectory(sourceURL, manifestName: manifestName)
        let manifestURL = sourceURL.appendingPathComponent(manifestName)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: manifestURL)
        var record = try decoder.decode(AppRecord.self, from: data)
        try AppPackageImportValidator.validatePackageContents(
            sourceURL: sourceURL,
            manifestName: manifestName,
            record: record
        )
        let packageDigest = try AppPackageImportValidator.contentDigestSHA256(
            sourceURL: sourceURL,
            manifestName: manifestName
        )
        let trustPolicy = trustedSignaturePublicKeys.map { keys in
            AppPackageTrustPolicy(
                trustedSignatureKeys: keys.map {
                    AppPackageTrustPolicy.TrustedSignatureKey(keyId: $0.key, publicKey: $0.value)
                }
            )
        } ?? packageTrustPolicy
        let signatureEvaluation = try AppPackageImportValidator.signatureEvaluation(
            sourceURL: sourceURL,
            packageDigestSHA256: packageDigest,
            trustPolicy: trustPolicy
        )
        let sourceSlug = record.slug
        let sourceOriginClass = record.originClass
        let resolvedSlug = try uniqueSlug(preferred: record.slug, name: record.name, includingFilesystem: true)
        let destinationURL = directory(forSlug: resolvedSlug)
        guard sourceURL.standardizedFileURL.path != destinationURL.standardizedFileURL.path else {
            throw AppsStoreImportError.sourceAlreadyManaged(sourceURL.path)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        record.slug = resolvedSlug
        record.originClass = originClass
        record.packageProvenance = AppPackageProvenance(
            sourcePath: sourceURL.standardizedFileURL.path,
            sourceSlug: sourceSlug,
            sourceOriginClass: sourceOriginClass,
            signatureStatus: signatureEvaluation.status,
            signatureKeyId: signatureEvaluation.keyId,
            signatureTrustSource: signatureEvaluation.trustSource,
            packageDigestSHA256: packageDigest
        )
        if originClass == .imported || originClass == .marketplace {
            record.activationReview = nil
        }
        record.updatedAt = Date()
        try writeManifest(record)
        try appendTrustAudit(
            app: record,
            eventType: .packageImported,
            reason: record.packageProvenance?.reviewReason ?? "Imported package requires local review before activation."
        )
        upsertInMemory(record)
        reloadFromDisk()
        return record
    }

    @discardableResult
    func approveActivation(_ record: AppRecord, riskMap: AppCapabilityRiskMap) throws -> AppRecord {
        var updated = record
        updated.activationReview = AppActivationReview(riskMapSource: riskMap.source)
        try update(updated)
        try appendTrustAudit(
            app: updated,
            eventType: .activationApproved,
            riskMap: riskMap,
            reason: "Activation approved after reviewing origin, capabilities, risk, and provenance."
        )
        return updated
    }

    // MARK: - File I/O for the WKURLSchemeHandler

    /// Look up a file inside an app's folder and return its bytes plus
    /// a guessed MIME type. Returns nil when the slug or path is bogus
    /// or when the file is outside the app's folder (path traversal
    /// guard via `URL.resolvingSymlinksInPath` + prefix check).
    func readFile(slug: String, relativePath: String) -> (data: Data, mimeType: String)? {
        let appDir = directory(forSlug: slug)
        let trimmed = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let resolvedName = trimmed.isEmpty ? "index.html" : trimmed
        let target = appDir
            .appendingPathComponent(resolvedName)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let resolvedAppDir = appDir.standardizedFileURL.resolvingSymlinksInPath()
        // Path traversal guard: ensure target is still under appDir.
        guard target.path.hasPrefix(resolvedAppDir.path + "/") || target.path == resolvedAppDir.path else {
            return nil
        }
        guard fileManager.fileExists(atPath: target.path) else { return nil }
        guard let data = try? Data(contentsOf: target) else { return nil }
        return (data, AppsStore.guessMimeType(forPath: target.path))
    }

    /// Bytes of the SDK script. Loaded lazily so consumers can flip the
    /// inline JS implementation without rebuilding any other types.
    var sdkScriptJS: String { ClawixAppsSDKJS }

    func record(forSlug slug: String) -> AppRecord? {
        apps.first(where: { $0.slug == slug })
    }

    func record(forId id: UUID) -> AppRecord? {
        apps.first(where: { $0.id == id })
    }

    func directory(forSlug slug: String) -> URL {
        rootURL.appendingPathComponent(slug)
    }

    func trustAuditURL(for record: AppRecord) -> URL {
        directory(forSlug: record.slug).appendingPathComponent(AppTrustAudit.filename, isDirectory: false)
    }

    func highRiskActionAuditURL(for record: AppRecord) -> URL {
        directory(forSlug: record.slug).appendingPathComponent(AppHighRiskActionAudit.filename, isDirectory: false)
    }

    // MARK: - Internals

    private func ensureRootExists() {
        if !fileManager.fileExists(atPath: rootURL.path) {
            try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
    }

    private func writeManifest(_ record: AppRecord) throws {
        let dir = directory(forSlug: record.slug)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifestURL = dir.appendingPathComponent(manifestName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(record)
        try data.write(to: manifestURL, options: .atomic)
    }

    private func appendTrustAudit(
        app: AppRecord,
        eventType: AppTrustAuditEvent.EventType,
        riskMap: AppCapabilityRiskMap? = nil,
        reason: String
    ) throws {
        try AppTrustAudit.append(
            app: app,
            eventType: eventType,
            riskMap: riskMap,
            reason: reason,
            auditURL: trustAuditURL(for: app)
        )
    }

    private func upsertInMemory(_ record: AppRecord) {
        if let index = apps.firstIndex(where: { $0.id == record.id || $0.slug == record.slug }) {
            apps[index] = record
        } else {
            apps.append(record)
        }
        apps = apps.sorted(by: AppsStore.compareForSidebar)
    }

    private func removeInMemory(_ record: AppRecord) {
        apps.removeAll { $0.id == record.id || $0.slug == record.slug }
        lastSeenMtime[record.slug] = nil
    }

    private func uniqueSlug(
        preferred: String?,
        name: String,
        includingFilesystem: Bool = false
    ) throws -> String {
        let base = AppsStore.normalizedSlug(from: preferred?.isEmpty == false ? preferred! : name)
        guard !base.isEmpty else {
            throw NSError(domain: "AppsStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot derive a slug from name '\(name)'"])
        }
        // Disambiguate "todos" → "todos-2" → "todos-3" if needed.
        let existing = Set(apps.map(\.slug))
        if !existing.contains(base), !slugExistsOnDisk(base, enabled: includingFilesystem) { return base }
        var counter = 2
        while existing.contains("\(base)-\(counter)") || slugExistsOnDisk("\(base)-\(counter)", enabled: includingFilesystem) {
            counter += 1
            if counter > 999 {
                throw NSError(domain: "AppsStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "Too many slugs starting with '\(base)'"])
            }
        }
        return "\(base)-\(counter)"
    }

    private func slugExistsOnDisk(_ slug: String, enabled: Bool) -> Bool {
        enabled && fileManager.fileExists(atPath: directory(forSlug: slug).path)
    }

    /// Lowercase, hyphen-separated, alphanumeric only. "Hello, World!" → "hello-world".
    static func normalizedSlug(from raw: String) -> String {
        let lowered = raw.lowercased()
        var result = ""
        var lastWasDash = false
        for scalar in lowered.unicodeScalars {
            if (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") {
                result.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash, !result.isEmpty {
                result.append("-")
                lastWasDash = true
            }
        }
        if result.hasSuffix("-") { result.removeLast() }
        return result
    }

    private static func compareForSidebar(_ lhs: AppRecord, _ rhs: AppRecord) -> Bool {
        if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
        let lOpened = lhs.lastOpenedAt ?? .distantPast
        let rOpened = rhs.lastOpenedAt ?? .distantPast
        if lOpened != rOpened { return lOpened > rOpened }
        return lhs.createdAt > rhs.createdAt
    }

    private func startPollingTimer() {
        // 4s is fast enough that the agent writing a new manifest is
        // visible "in the next breath" without burning CPU.
        let timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reloadFromDisk()
            }
        }
        timer.tolerance = 1.0
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer
    }

    private static func loadSnapshot(rootURL: URL, manifestName: String) async throws -> AppsSnapshot {
        try await Task.detached(priority: .utility) {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                return AppsSnapshot(apps: [], mtimes: [:])
            }

            var found: [AppRecord] = []
            var newMtimes: [String: Date] = [:]
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            for entry in entries {
                try Task.checkCancellation()
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else { continue }
                let manifestURL = entry.appendingPathComponent(manifestName)
                guard FileManager.default.fileExists(atPath: manifestURL.path) else { continue }
                do {
                    let mtime = (try manifestURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let data = try Data(contentsOf: manifestURL)
                    let record = try decoder.decode(AppRecord.self, from: data)
                    found.append(record)
                    newMtimes[record.slug] = mtime
                } catch {
                    // Keep malformed manifests local to their app folder so
                    // one broken custom surface cannot break the Apps shell.
                    continue
                }
            }
            return AppsSnapshot(apps: found, mtimes: newMtimes)
        }.value
    }

    static func guessMimeType(forPath path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs":   return "application/javascript; charset=utf-8"
        case "css":         return "text/css; charset=utf-8"
        case "json":        return "application/json; charset=utf-8"
        case "svg":         return "image/svg+xml"
        case "png":         return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":         return "image/gif"
        case "webp":        return "image/webp"
        case "ico":         return "image/x-icon"
        case "woff":        return "font/woff"
        case "woff2":       return "font/woff2"
        case "ttf":         return "font/ttf"
        case "otf":         return "font/otf"
        case "wasm":        return "application/wasm"
        case "txt", "md":   return "text/plain; charset=utf-8"
        default:            return "application/octet-stream"
        }
    }

    static func placeholderIndexHTML(name: String) -> String {
        // Minimal, on-brand "this app is empty" page so opening a fresh
        // app slug doesn't show a blank window. The agent overwrites it
        // as soon as it writes any real index.html.
        let escapedName = name
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>\(escapedName)</title>
        <style>
        :root{color-scheme:dark light}
        html,body{margin:0;height:100%;font-family:-apple-system,BlinkMacSystemFont,sans-serif;
            display:flex;align-items:center;justify-content:center;background:#0e0e10;color:#aaa;}
        .wrap{text-align:center;padding:40px;max-width:520px}
        h1{font-weight:500;font-size:22px;color:#eee;margin:0 0 8px}
        p{margin:0;font-size:14px;line-height:1.5}
        code{background:#1e1e22;padding:2px 6px;border-radius:4px;font-size:12.5px;color:#ddd}
        </style></head><body>
        <div class="wrap">
        <h1>\(escapedName)</h1>
        <p>This app has no content yet. Ask the agent to build it, or drop files into <code>~/.claw/apps/</code>.</p>
        </div></body></html>
        """
    }
}

enum AppsStoreImportError: LocalizedError, Equatable {
    case missingManifest(String)
    case sourceAlreadyManaged(String)
    case sourceNotDirectory(String)
    case missingRenderEntry(String)
    case symlinkNotAllowed(String)
    case hostOwnedFileNotAllowed(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest(let path):
            return "App package is missing manifest.json: \(path)"
        case .sourceAlreadyManaged(let path):
            return "App package is already managed by this Apps store: \(path)"
        case .sourceNotDirectory(let path):
            return "App package source is not a directory: \(path)"
        case .missingRenderEntry(let entry):
            return "App package is missing required render entry: \(entry)"
        case .symlinkNotAllowed(let path):
            return "App package contains a symbolic link, which is not allowed: \(path)"
        case .hostOwnedFileNotAllowed(let path):
            return "App package contains a host-owned audit file, which is not allowed on import: \(path)"
        }
    }
}
