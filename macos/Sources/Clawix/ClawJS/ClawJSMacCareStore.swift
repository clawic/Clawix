import Combine
import Foundation

@MainActor
final class ClawJSMacCareStore: ObservableObject {
    typealias LoadReportOperation = @MainActor () async throws -> ClawJSMacCareClient.Report
    typealias ListScansOperation = @MainActor () async throws -> ClawJSMacCareClient.ScanList
    typealias LoadScanOperation = @MainActor (_ id: String) async throws -> ClawJSMacCareClient.ScanDetail
    typealias PreviewFinalizerOperation = @MainActor (_ actionPlan: ClawJSMacCareClient.ActionPlan) async throws -> ClawJSMacCareClient.FinalizerPreview

    static let shared = ClawJSMacCareStore()

    @Published private(set) var report: ClawJSMacCareClient.Report?
    @Published private(set) var scanList: ClawJSMacCareClient.ScanList?
    @Published private(set) var selectedScan: ClawJSMacCareClient.ScanDetail?
    @Published private(set) var finalizerPreview: ClawJSMacCareClient.FinalizerPreview?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingScan = false
    @Published private(set) var isLoadingFinalizerPreview = false
    @Published private(set) var errorMessage: String?

    private let loadReportOperation: LoadReportOperation
    private let listScansOperation: ListScansOperation
    private let loadScanOperation: LoadScanOperation
    private let previewFinalizerOperation: PreviewFinalizerOperation
    private var refreshTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var finalizerPreviewTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var scanGeneration = 0
    private var finalizerPreviewGeneration = 0

    init(
        client: ClawJSMacCareClient = ClawJSMacCareClient(),
        autoLoad: Bool = true,
        loadReportOperation: LoadReportOperation? = nil,
        listScansOperation: ListScansOperation? = nil,
        loadScanOperation: LoadScanOperation? = nil,
        previewFinalizerOperation: PreviewFinalizerOperation? = nil
    ) {
        self.loadReportOperation = loadReportOperation ?? {
            try await client.loadReport()
        }
        self.listScansOperation = listScansOperation ?? {
            try await client.listScans()
        }
        self.loadScanOperation = loadScanOperation ?? { id in
            try await client.loadScan(id: id)
        }
        self.previewFinalizerOperation = previewFinalizerOperation ?? { actionPlan in
            try await client.previewFinalizer(actionPlan: actionPlan)
        }
        if autoLoad {
            reload()
        }
    }

    deinit {
        refreshTask?.cancel()
        scanTask?.cancel()
        finalizerPreviewTask?.cancel()
    }

    var isLoading: Bool {
        isRefreshing || isLoadingScan || isLoadingFinalizerPreview
    }

    var latestScan: ClawJSMacCareClient.ScanSummary? {
        scanList?.scans.first
    }

    var latestScanId: String? {
        latestScan?.id
    }

    var totalPersistedCandidates: Int {
        scanList?.scans.reduce(0) { $0 + $1.candidateCount } ?? 0
    }

    var totalPersistedSizeBytes: Int {
        scanList?.scans.reduce(0) { $0 + ($1.summary.totalSizeBytes ?? 0) } ?? 0
    }

    var hasDestructiveActionPlan: Bool {
        if report?.safety.destructiveActions.isEmpty == false {
            return true
        }
        if scanList?.scans.contains(where: { ($0.summary.destructiveActions ?? 0) > 0 }) == true {
            return true
        }
        if selectedScan?.safety?.destructiveActions.isEmpty == false {
            return true
        }
        return false
    }

    func reload() {
        _ = startRefresh()
    }

    func refresh() async {
        await startRefresh().value
    }

    func selectScan(id: String) async {
        await startScanLoad(id: id).value
    }

    func clearSelection() {
        scanGeneration += 1
        finalizerPreviewGeneration += 1
        scanTask?.cancel()
        finalizerPreviewTask?.cancel()
        scanTask = nil
        finalizerPreviewTask = nil
        selectedScan = nil
        finalizerPreview = nil
        isLoadingScan = false
        isLoadingFinalizerPreview = false
    }

    func previewFinalizerForSelectedScan() async {
        guard let actionPlan = selectedScan?.actionPlan else {
            finalizerPreview = nil
            return
        }
        await startFinalizerPreview(actionPlan: actionPlan).value
    }

    func cancelSurfaceWork() {
        refreshGeneration += 1
        scanGeneration += 1
        finalizerPreviewGeneration += 1
        refreshTask?.cancel()
        scanTask?.cancel()
        finalizerPreviewTask?.cancel()
        refreshTask = nil
        scanTask = nil
        finalizerPreviewTask = nil
        isRefreshing = false
        isLoadingScan = false
        isLoadingFinalizerPreview = false
    }

    @discardableResult
    private func startRefresh() -> Task<Void, Never> {
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runRefresh(generation: generation)
        }
        refreshTask = task
        return task
    }

    private func runRefresh(generation: Int) async {
        guard generation == refreshGeneration else { return }
        isRefreshing = true
        errorMessage = nil
        do {
            let report = try await loadReportOperation()
            try Task.checkCancellation()
            let scanList = try await listScansOperation()
            try Task.checkCancellation()
            guard generation == refreshGeneration else { return }
            self.report = report
            self.scanList = scanList
            if let selectedScan, !scanList.scans.contains(where: { $0.id == selectedScan.scan.id }) {
                self.selectedScan = nil
            }
            finishRefreshIfCurrent(generation)
        } catch is CancellationError {
            finishRefreshIfCurrent(generation)
        } catch {
            guard generation == refreshGeneration else { return }
            errorMessage = Self.displayMessage(for: error)
            finishRefreshIfCurrent(generation)
        }
    }

    private func finishRefreshIfCurrent(_ generation: Int) {
        guard generation == refreshGeneration else { return }
        isRefreshing = false
        refreshTask = nil
    }

    @discardableResult
    private func startScanLoad(id: String) -> Task<Void, Never> {
        scanGeneration += 1
        let generation = scanGeneration
        scanTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runScanLoad(id: id, generation: generation)
        }
        scanTask = task
        return task
    }

    private func runScanLoad(id: String, generation: Int) async {
        guard generation == scanGeneration else { return }
        isLoadingScan = true
        errorMessage = nil
        do {
            let detail = try await loadScanOperation(id)
            try Task.checkCancellation()
            guard generation == scanGeneration else { return }
            selectedScan = detail
            finalizerPreview = nil
            finishScanLoadIfCurrent(generation)
        } catch is CancellationError {
            finishScanLoadIfCurrent(generation)
        } catch {
            guard generation == scanGeneration else { return }
            errorMessage = Self.displayMessage(for: error)
            finishScanLoadIfCurrent(generation)
        }
    }

    private func finishScanLoadIfCurrent(_ generation: Int) {
        guard generation == scanGeneration else { return }
        isLoadingScan = false
        scanTask = nil
    }

    @discardableResult
    private func startFinalizerPreview(actionPlan: ClawJSMacCareClient.ActionPlan) -> Task<Void, Never> {
        finalizerPreviewGeneration += 1
        let generation = finalizerPreviewGeneration
        finalizerPreviewTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runFinalizerPreview(actionPlan: actionPlan, generation: generation)
        }
        finalizerPreviewTask = task
        return task
    }

    private func runFinalizerPreview(actionPlan: ClawJSMacCareClient.ActionPlan, generation: Int) async {
        guard generation == finalizerPreviewGeneration else { return }
        isLoadingFinalizerPreview = true
        errorMessage = nil
        do {
            let preview = try await previewFinalizerOperation(actionPlan)
            try Task.checkCancellation()
            guard generation == finalizerPreviewGeneration else { return }
            finalizerPreview = preview
            finishFinalizerPreviewIfCurrent(generation)
        } catch is CancellationError {
            finishFinalizerPreviewIfCurrent(generation)
        } catch {
            guard generation == finalizerPreviewGeneration else { return }
            errorMessage = Self.displayMessage(for: error)
            finishFinalizerPreviewIfCurrent(generation)
        }
    }

    private func finishFinalizerPreviewIfCurrent(_ generation: Int) {
        guard generation == finalizerPreviewGeneration else { return }
        isLoadingFinalizerPreview = false
        finalizerPreviewTask = nil
    }

    private static func displayMessage(for error: Error) -> String {
        let message = (error as NSError).localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Mac Care data could not be loaded." : message
    }
}
