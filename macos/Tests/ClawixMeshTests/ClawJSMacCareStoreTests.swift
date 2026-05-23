import XCTest
@testable import Clawix

@MainActor
final class ClawJSMacCareStoreTests: XCTestCase {
    func testRefreshLoadsReportAndPersistedScanHistory() async {
        let store = makeStore()

        await store.refresh()

        XCTAssertEqual(store.report?.status, "read_only_foundation")
        XCTAssertEqual(store.scanList?.status, "read_only_scan_history")
        XCTAssertEqual(store.latestScanId, "mac-care-scan-1")
        XCTAssertEqual(store.totalPersistedCandidates, 3)
        XCTAssertEqual(store.totalPersistedSizeBytes, 84)
        XCTAssertFalse(store.hasDestructiveActionPlan)
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.errorMessage)
    }

    func testSelectScanLoadsReadOnlyDetail() async {
        var requestedIds: [String] = []
        let store = makeStore(loadScanOperation: { id in
            requestedIds.append(id)
            return Self.detail(id: id, destructiveActions: [])
        })

        await store.selectScan(id: "mac-care-scan-2")

        XCTAssertEqual(requestedIds, ["mac-care-scan-2"])
        XCTAssertEqual(store.selectedScan?.scan.id, "mac-care-scan-2")
        XCTAssertEqual(store.selectedScan?.candidates.first?.selection, "unselected")
        XCTAssertFalse(store.hasDestructiveActionPlan)
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.errorMessage)
    }

    func testPreviewFinalizerForSelectedScanLoadsPlanOnlyPreview() async {
        var previewedPlanIds: [String] = []
        let store = makeStore(
            loadScanOperation: { id in Self.destructiveDetail(id: id) },
            previewFinalizerOperation: { actionPlan in
                previewedPlanIds.append(actionPlan.id)
                return Self.finalizerPreview(sourcePlanId: actionPlan.id)
            }
        )

        await store.selectScan(id: "mac-care-scan-finalizer")
        await store.previewFinalizerForSelectedScan()

        XCTAssertEqual(previewedPlanIds, ["mac-care-finalizer-plan"])
        XCTAssertEqual(store.finalizerPreview?.status, "finalizer_preview")
        XCTAssertFalse(store.finalizerPreview?.willExecute ?? true)
        XCTAssertFalse(store.finalizerPreview?.receiptIssued ?? true)
        XCTAssertEqual(store.finalizerPreview?.actions.first?.candidateId, "candidate-trash")
        XCTAssertEqual(store.finalizerPreview?.summary.receiptsIssued, 0)
        XCTAssertEqual(store.finalizerPreview?.safety.requiredAuthority, "signed_host_human_confirmed")
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.errorMessage)
    }

    func testRefreshFailureLeavesPreviousDataAndPublishesError() async {
        enum TestError: LocalizedError {
            case failed

            var errorDescription: String? {
                "history unavailable"
            }
        }
        var shouldFail = false
        let store = makeStore(listScansOperation: {
            if shouldFail {
                throw TestError.failed
            }
            return Self.scanList()
        })
        await store.refresh()
        shouldFail = true

        await store.refresh()

        XCTAssertEqual(store.scanList?.scans.first?.id, "mac-care-scan-1")
        XCTAssertEqual(store.errorMessage, "history unavailable")
        XCTAssertFalse(store.isLoading)
    }

    func testSecondRefreshSuppressesStaleReportAndHistory() async {
        let staleStarted = expectation(description: "stale refresh started")
        let staleReturned = expectation(description: "stale refresh returned")
        let freshReturned = expectation(description: "fresh refresh returned")
        var calls = 0
        let store = makeStore(loadReportOperation: {
            calls += 1
            if calls == 1 {
                staleStarted.fulfill()
                try? await Task.sleep(nanoseconds: 100_000_000)
                staleReturned.fulfill()
                return Self.report(status: "stale")
            }
            freshReturned.fulfill()
            return Self.report(status: "fresh")
        })

        let first = Task { await store.refresh() }
        await fulfillment(of: [staleStarted], timeout: 1)
        let second = Task { await store.refresh() }

        await fulfillment(of: [freshReturned, staleReturned], timeout: 1)
        await first.value
        await second.value
        XCTAssertEqual(store.report?.status, "fresh")
        XCTAssertFalse(store.isLoading)
    }

    func testCancelSurfaceWorkSuppressesLateScanDetail() async {
        let loadStarted = expectation(description: "scan detail load started")
        let loadReturned = expectation(description: "scan detail load returned")
        let store = makeStore(loadScanOperation: { id in
            loadStarted.fulfill()
            try? await Task.sleep(nanoseconds: 50_000_000)
            loadReturned.fulfill()
            return Self.detail(id: id, destructiveActions: [])
        })

        let task = Task { await store.selectScan(id: "mac-care-scan-closed") }
        await fulfillment(of: [loadStarted], timeout: 1)
        store.cancelSurfaceWork()

        await fulfillment(of: [loadReturned], timeout: 1)
        await task.value
        XCTAssertNil(store.selectedScan)
        XCTAssertFalse(store.isLoading)
    }

    private func makeStore(
        loadReportOperation: ClawJSMacCareStore.LoadReportOperation? = nil,
        listScansOperation: ClawJSMacCareStore.ListScansOperation? = nil,
        loadScanOperation: ClawJSMacCareStore.LoadScanOperation? = nil,
        previewFinalizerOperation: ClawJSMacCareStore.PreviewFinalizerOperation? = nil
    ) -> ClawJSMacCareStore {
        ClawJSMacCareStore(
            autoLoad: false,
            loadReportOperation: loadReportOperation ?? { Self.report() },
            listScansOperation: listScansOperation ?? { Self.scanList() },
            loadScanOperation: loadScanOperation ?? { id in Self.detail(id: id, destructiveActions: []) },
            previewFinalizerOperation: previewFinalizerOperation ?? { actionPlan in Self.finalizerPreview(sourcePlanId: actionPlan.id) }
        )
    }

    private static func report(status: String = "read_only_foundation") -> ClawJSMacCareClient.Report {
        ClawJSMacCareClient.Report(
            version: 1,
            status: status,
            routes: [
                .init(
                    id: "mac_care.route.user_caches",
                    family: "user_cache",
                    label: "User caches",
                    pathPattern: "{home}/Library/Caches",
                    source: "home",
                    sensitivity: "user_data",
                    requiredPermissionIds: ["mac.permission.files_desktop_documents_downloads"],
                    owner: "application",
                    evidenceLevel: "macos_convention",
                    mutability: "review_required",
                    consumerIntents: ["cleanup", "index", "performance"],
                    notes: nil
                )
            ],
            groups: [],
            actionPlan: actionPlan(),
            safety: safety(destructiveActions: []),
            sidecar: sidecar(),
            executionPolicy: .init(
                agentCanExecuteDestructiveActions: false,
                testCanExecuteDestructiveActions: false,
                destructiveExecutionAuthority: "signed_host_human_confirmed",
                realFilesystemMutationInFoundationReport: false
            )
        )
    }

    private static func scanList() -> ClawJSMacCareClient.ScanList {
        ClawJSMacCareClient.ScanList(
            version: 1,
            status: "read_only_scan_history",
            scans: [
                summary(id: "mac-care-scan-1", candidateCount: 2, totalSizeBytes: 42),
                summary(id: "mac-care-scan-2", candidateCount: 1, totalSizeBytes: 42)
            ],
            sidecar: sidecar()
        )
    }

    private static func detail(id: String, destructiveActions: [String]) -> ClawJSMacCareClient.ScanDetail {
        ClawJSMacCareClient.ScanDetail(
            version: 1,
            status: "read_only_scan_detail",
            scan: summary(id: id, candidateCount: 1, totalSizeBytes: 42),
            candidates: [
                .init(
                    id: "\(id)-candidate-1",
                    routeId: "mac_care.route.user_caches",
                    path: "/tmp/home/Library/Caches/blob",
                    action: "review",
                    selection: "unselected",
                    confidence: 0.85,
                    sizeBytes: 42,
                    evidence: ["read_only_file_stat"],
                    warnings: ["large_file"],
                    metadata: .init(
                        displayName: "blob",
                        groupId: "mac_care.group.user_caches",
                        moduleId: "mac_care.module.user_caches"
                    )
                )
            ],
            actionPlan: actionPlan(),
            safety: safety(destructiveActions: destructiveActions),
            sidecar: sidecar()
        )
    }

    private static func destructiveDetail(id: String) -> ClawJSMacCareClient.ScanDetail {
        ClawJSMacCareClient.ScanDetail(
            version: 1,
            status: "read_only_scan_detail",
            scan: summary(id: id, candidateCount: 1, totalSizeBytes: 42),
            candidates: [],
            actionPlan: destructiveActionPlan(),
            safety: safety(destructiveActions: ["move_to_trash"]),
            sidecar: sidecar()
        )
    }

    private static func summary(
        id: String,
        candidateCount: Int,
        totalSizeBytes: Int
    ) -> ClawJSMacCareClient.ScanSummary {
        ClawJSMacCareClient.ScanSummary(
            id: id,
            moduleId: "mac_care.scan.wave_1",
            status: "completed",
            startedAt: "2026-05-21T00:00:00.000Z",
            completedAt: "2026-05-21T00:00:00.000Z",
            summary: .init(
                totalCandidates: candidateCount,
                totalSizeBytes: totalSizeBytes,
                destructiveActions: 0
            ),
            metadata: .init(
                homeDir: "/tmp/home",
                modules: ["mac_care.module.user_caches"]
            ),
            candidateCount: candidateCount,
            actionPlanCount: 1
        )
    }

    private static func actionPlan() -> ClawJSMacCareClient.ActionPlan {
        ClawJSMacCareClient.ActionPlan(
            id: "mac-care-scan-1-plan",
            createdAt: "2026-05-21T00:00:00.000Z",
            groups: [],
            executionAuthority: "agent_plan_only",
            requestedBy: "agent"
        )
    }

    private static func destructiveActionPlan() -> ClawJSMacCareClient.ActionPlan {
        ClawJSMacCareClient.ActionPlan(
            id: "mac-care-finalizer-plan",
            createdAt: "2026-05-21T00:00:00.000Z",
            groups: [
                .init(
                    id: "mac_care.group.downloads",
                    moduleId: "mac_care.module.downloads",
                    title: "Downloads",
                    routeIds: ["mac_care.route.downloads"],
                    candidates: [
                        .init(
                            id: "candidate-trash",
                            routeId: "mac_care.route.downloads",
                            path: "/tmp/home/Downloads/old.dmg",
                            displayName: "old.dmg",
                            sizeBytes: 42,
                            action: "move_to_trash",
                            selection: "blocked",
                            confidence: 0.8,
                            evidence: ["fixture"],
                            warnings: ["large_file"]
                        )
                    ]
                )
            ],
            executionAuthority: "agent_plan_only",
            requestedBy: "agent"
        )
    }

    private static func finalizerPreview(sourcePlanId: String) -> ClawJSMacCareClient.FinalizerPreview {
        ClawJSMacCareClient.FinalizerPreview(
            version: 1,
            status: "finalizer_preview",
            createdAt: "2026-05-21T00:00:00.000Z",
            sourcePlanId: sourcePlanId,
            willExecute: false,
            receiptIssued: false,
            executionAuthority: "signed_host_human_confirmed",
            actions: [
                .init(
                    id: "finalizer-preview:candidate-trash",
                    candidateId: "candidate-trash",
                    routeId: "mac_care.route.downloads",
                    path: "/tmp/home/Downloads/old.dmg",
                    displayName: "old.dmg",
                    action: "move_to_trash",
                    selection: "blocked",
                    destructive: true,
                    executionAuthority: "signed_host_human_confirmed",
                    requiresHumanConfirmation: true,
                    blockedForAgents: true,
                    rollback: .init(level: "best_effort", notes: "Signed host may attempt restore from Trash while the item remains available."),
                    audit: .init(event: "mac_care.finalizer.move_to_trash.request", receiptRequired: true, receiptStatus: "not_issued"),
                    warnings: ["preview_only_no_execution"]
                )
            ],
            summary: .init(
                totalCandidates: 1,
                destructiveCandidates: 1,
                blockedForAgents: 1,
                receiptsIssued: 0
            ),
            safety: safety(destructiveActions: ["move_to_trash"]),
            sidecar: sidecar(),
            executionPolicy: .init(
                agentCanExecuteDestructiveActions: false,
                testCanExecuteDestructiveActions: false,
                destructiveExecutionAuthority: "signed_host_human_confirmed",
                realFilesystemMutationInFoundationReport: false
            )
        )
    }

    private static func safety(destructiveActions: [String]) -> ClawJSMacCareClient.SafetyDecision {
        ClawJSMacCareClient.SafetyDecision(
            allowed: destructiveActions.isEmpty,
            requiredAuthority: destructiveActions.isEmpty ? "none" : "signed_host_human_confirmed",
            destructiveActions: destructiveActions,
            reasons: []
        )
    }

    private static func sidecar() -> ClawJSMacCareClient.Sidecar {
        ClawJSMacCareClient.Sidecar(
            filename: "mac_care.sqlite",
            surfaceId: "claw.database.macCare",
            path: "~/.claw/data/mac_care.sqlite"
        )
    }
}
