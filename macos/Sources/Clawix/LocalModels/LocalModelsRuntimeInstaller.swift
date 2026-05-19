import Foundation
import CryptoKit

/// Installs and verifies the local LLM runtime outside the app bundle.
@MainActor
final class LocalModelsRuntimeInstaller: NSObject, ObservableObject {
    typealias DownloadOperation = @MainActor () async throws -> URL
    typealias ArchiveOperation = @Sendable (_ tarball: URL) async throws -> Void

    static let shared = LocalModelsRuntimeInstaller()

    nonisolated static let pinnedVersion = "v0.23.1"

    nonisolated static let pinnedDownloadURL = URL(
        string: "https://github.com/ollama/ollama/releases/download/v0.23.1/ollama-darwin.tgz"
    )!

    nonisolated static let pinnedSHA256Base64 = "YpWG/xp201GnufV+sZhe+QPuLm/0mXp8VXOWTIPzehY="

    nonisolated static let pinnedSizeBytes: Int64 = 133_703_316

    enum State: Equatable {
        case notInstalled
        case installing(progress: Double, downloadedBytes: Int64)
        case extracting
        case installed(version: String)
        case updateAvailable(installed: String)
        case failed(message: String)
    }

    @Published private(set) var state: State = .notInstalled

    private var session: URLSession?
    private var downloadTask: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<URL, Error>?
    private let downloadOperation: DownloadOperation?
    private let verifyOperation: ArchiveOperation?
    private let extractOperation: ArchiveOperation?

    init(
        downloadOperation: DownloadOperation? = nil,
        verifyOperation: ArchiveOperation? = nil,
        extractOperation: ArchiveOperation? = nil,
        refreshOnInit: Bool = true
    ) {
        self.downloadOperation = downloadOperation
        self.verifyOperation = verifyOperation
        self.extractOperation = extractOperation
        super.init()
        if refreshOnInit {
            refresh()
        }
    }

    // MARK: - Public API

    var isInstalled: Bool {
        if case .installed = state { return true }
        return false
    }

    func refresh() {
        if let v = installedVersion() {
            state = (v == Self.pinnedVersion)
                ? .installed(version: v)
                : .updateAvailable(installed: v)
        } else {
            state = .notInstalled
        }
    }

    func install() async {
        if case .installed(let v) = state, v == Self.pinnedVersion { return }
        if case .installing = state { return }
        if case .extracting = state { return }

        do {
            try Self.prepareParentDirectory()

            let tarball: URL
            if let downloadOperation {
                tarball = try await downloadOperation()
            } else {
                tarball = try await download()
            }
            try Task.checkCancellation()
            try await runArchiveOperation(tarball: tarball, injected: verifyOperation) {
                try Self.verify(tarball: tarball)
            }
            try Task.checkCancellation()

            self.state = .extracting

            try await runArchiveOperation(tarball: tarball, injected: extractOperation) {
                try await Self.extract(tarball: tarball)
                try Self.writeVersionFile()
                try? FileManager.default.removeItem(at: tarball)
            }
            try Task.checkCancellation()

            self.state = .installed(version: Self.pinnedVersion)
        } catch is CancellationError {
            self.state = .notInstalled
        } catch {
            self.state = .failed(message: error.localizedDescription)
        }
    }

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        session?.invalidateAndCancel()
        session = nil
        resumeContinuation(with: .failure(CancellationError()))
    }

    func uninstall() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: Self.runtimeRoot.path) {
            try fm.removeItem(at: Self.runtimeRoot)
        }
        state = .notInstalled
    }

    func installedVersion() -> String? {
        guard let data = try? Data(contentsOf: Self.versionFile) else { return nil }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - On-disk layout

    nonisolated static var runtimeRoot: URL {
        applicationSupportRoot.appendingPathComponent("runtime", isDirectory: true)
    }

    nonisolated static var versionFile: URL {
        runtimeRoot.appendingPathComponent("version", isDirectory: false)
    }

    /// The upstream tarball ships the binary at the tarball root (next
    /// to its `.dylib`s, `.so`s and `mlx_metal_v*/` directories), not
    /// under `bin/`. Confirmed against v0.23.1 by extracting locally.
    nonisolated static var binaryURL: URL {
        runtimeRoot.appendingPathComponent("ollama", isDirectory: false)
    }

    /// Directory dyld must search at runtime to load the libs that ship
    /// alongside the binary. Set via `DYLD_LIBRARY_PATH` when spawning.
    nonisolated static var libraryPath: URL { runtimeRoot }

    nonisolated static var applicationSupportRoot: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return base
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.clawix, isDirectory: true)
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.localModels, isDirectory: true)
    }

    private nonisolated static func prepareParentDirectory() throws {
        try FileManager.default.createDirectory(
            at: applicationSupportRoot,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Download

    private func download() async throws -> URL {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 30 * 60
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            self.continuation = cont
            self.state = .installing(progress: 0, downloadedBytes: 0)
            let task = session.downloadTask(with: Self.pinnedDownloadURL)
            self.downloadTask = task
            task.resume()
        }
    }

    func updateDownloadProgress(progress: Double, downloadedBytes: Int64) {
        state = .installing(progress: progress, downloadedBytes: downloadedBytes)
    }

    func resumeContinuation(with result: Result<URL, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        downloadTask = nil
        session = nil
        switch result {
        case .success(let url): cont.resume(returning: url)
        case .failure(let err): cont.resume(throwing: err)
        }
    }

    private func runArchiveOperation(
        tarball: URL,
        injected: ArchiveOperation?,
        fallback: @escaping @Sendable () async throws -> Void
    ) async throws {
        if let injected {
            try await injected(tarball)
            return
        }
        let task = Task.detached(priority: .userInitiated) {
            try await fallback()
        }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: - Verify / extract (off the main actor)

    private nonisolated static func verify(tarball: URL) throws {
        let handle = try FileHandle(forReadingFrom: tarball)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            let chunk = autoreleasepool { (try? handle.read(upToCount: 1 << 20)) ?? Data() }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        let actual = Data(hasher.finalize()).base64EncodedString()
        guard actual == pinnedSHA256Base64 else {
            throw InstallerError.sha256Mismatch(expected: pinnedSHA256Base64, actual: actual)
        }
    }

    private nonisolated static func extract(tarball: URL) async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: runtimeRoot.path) {
            try fm.removeItem(at: runtimeRoot)
        }
        try fm.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)

        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xzf", tarball.path, "-C", runtimeRoot.path]
        let stderrPipe = Pipe()
        tar.standardError = stderrPipe
        tar.standardOutput = Pipe()

        let terminationStatus = try await withTaskCancellationHandler {
            try tar.run()
            return await withCheckedContinuation { continuation in
                tar.terminationHandler = { process in
                    continuation.resume(returning: process.terminationStatus)
                }
            }
        } onCancel: {
            if tar.isRunning {
                tar.terminate()
            }
        }

        try Task.checkCancellation()
        guard terminationStatus == 0 else {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "exit \(terminationStatus)"
            throw InstallerError.extractionFailed(message: message)
        }

        guard fm.isExecutableFile(atPath: binaryURL.path) else {
            throw InstallerError.binaryMissing(expected: binaryURL.path)
        }
    }

    private nonisolated static func writeVersionFile() throws {
        let data = pinnedVersion.data(using: .utf8)!
        try data.write(to: versionFile, options: .atomic)
    }

    // MARK: - Errors

    enum InstallerError: LocalizedError {
        case sha256Mismatch(expected: String, actual: String)
        case extractionFailed(message: String)
        case binaryMissing(expected: String)

        var errorDescription: String? {
            switch self {
            case .sha256Mismatch(let expected, let actual):
                return "Runtime checksum mismatch. Expected \(expected), got \(actual). Aborting for safety."
            case .extractionFailed(let message):
                return "Could not unpack runtime archive: \(message)"
            case .binaryMissing(let expected):
                return "Runtime extracted but the binary is missing at \(expected). Upstream layout may have changed."
            }
        }
    }
}
