import XCTest
@testable import Clawix

final class DiagnosticReportSupportTests: XCTestCase {
    func testDiagnosticEvidenceCategoriesMirrorPerformanceTaxonomy() {
        XCTAssertEqual(
            DiagnosticEvidenceCategory.performanceTaxonomyRawValues,
            PerfSignpost.allCases.map(\.rawValue)
        )
        XCTAssertTrue(DiagnosticEvidenceCategory.diagnosticsExport.isPerformanceTaxonomyCategory)
        XCTAssertTrue(DiagnosticEvidenceCategory.uiSidebar.isPerformanceTaxonomyCategory)
        XCTAssertFalse(DiagnosticEvidenceCategory.safetyReview.isPerformanceTaxonomyCategory)
    }

    func testDiagnosticRedactorRemovesSensitiveValues() {
        let apiKey = "sk-" + "1234567890abcdef"
        let githubToken = "ghp_" + "1234567890abcdefghijklmnopqrst"
        let sessionPath = "/Users/" + "example/.codex/sessions/2026/05/23/rollout-" + "2026-05-23T10-11-12-123-01234567-89ab-cdef-0123-456789abcdef.jsonl"
        let teamId = "ABCDE" + "12345"
        let bundleId = "com." + "clawix.private.real"
        let redacted = ClawixDiagnosticRedactor.redact(
            """
            path=/Users/example/project
            token=\(apiKey)
            authorization: Bearer \(githubToken)
            api_key="very-secret-value"
            secret://provider/main
            file:///Users/example/Desktop/report.json
            \(sessionPath)
            TEAM_ID: \(teamId)
            bundle_id \(bundleId)
            user alice@example.com
            prompt: "private task"
            """
        )

        XCTAssertFalse(redacted.contains("/Users/example"))
        XCTAssertFalse(redacted.contains("private task"))
        XCTAssertFalse(redacted.contains(apiKey))
        XCTAssertFalse(redacted.contains(githubToken))
        XCTAssertFalse(redacted.contains("very-secret-value"))
        XCTAssertFalse(redacted.contains("secret://"))
        XCTAssertFalse(redacted.contains("file://"))
        XCTAssertFalse(redacted.contains(sessionPath))
        XCTAssertFalse(redacted.contains(teamId))
        XCTAssertFalse(redacted.contains(bundleId))
        XCTAssertFalse(redacted.contains("alice@example.com"))
        XCTAssertTrue(redacted.contains("[redacted_path]"))
        XCTAssertTrue(redacted.contains("[redacted_secret]"))
        XCTAssertTrue(redacted.contains("[redacted_secret_ref]"))
        XCTAssertTrue(redacted.contains("[redacted_file_url]"))
        XCTAssertTrue(redacted.contains("[redacted_session]"))
        XCTAssertTrue(redacted.contains("[redacted_team_id]"))
        XCTAssertTrue(redacted.contains("[redacted_bundle_id]"))
        XCTAssertTrue(redacted.contains("[redacted_email]"))
    }

    func testProcessLogSinkRedactsProcessOutputBeforeWritingLog() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RedactedProcessLogSinkTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let logURL = tempRoot.appendingPathComponent("runtime.log")
        let sink = try ClawixRedactedProcessLogSink(logURL: logURL)
        let apiKey = "sk-" + "1234567890abcdef"
        let githubToken = "ghp_" + "1234567890abcdefghijklmnopqrst"
        let sessionPath = "/Users/" + "example/.codex/sessions/2026/05/23/rollout-" + "2026-05-23T10-11-12-123-01234567-89ab-cdef-0123-456789abcdef.jsonl"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "printf '%s\\n' \"$1\"; printf '%s\\n' \"$2\" >&2",
            "redaction-test",
            "prompt: private task token=\(apiKey)",
            "authorization: Bearer \(githubToken) path=\(sessionPath)"
        ]
        process.standardOutput = sink.stdoutPipe
        process.standardError = sink.stderrPipe

        try process.run()
        process.waitUntilExit()
        sink.close()

        let text = String(decoding: try Data(contentsOf: logURL), as: UTF8.self)
        XCTAssertFalse(text.contains("private task"))
        XCTAssertFalse(text.contains(apiKey))
        XCTAssertFalse(text.contains(githubToken))
        XCTAssertFalse(text.contains(sessionPath))
        XCTAssertTrue(text.contains("[redacted_prompt]"))
        XCTAssertTrue(text.contains("[redacted_secret]"))
        XCTAssertTrue(text.contains("[redacted_session]"))
    }

    func testFeedbackWriterCreatesRedactedAgentHandoffBundle() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FeedbackWriterTests-\(UUID().uuidString)", isDirectory: true)
        let bundleId = "com.example.clawix"
        let diagnosticsDir = ClawixDiagnosticStorageRoutes.diagnosticsDirectoryURL(
            applicationSupportRoot: tempRoot,
            bundleIdentifier: bundleId
        )
        try FileManager.default.createDirectory(at: diagnosticsDir, withIntermediateDirectories: true)
        try Data(#"{"residentBytes":1024}"#.utf8)
            .write(to: diagnosticsDir.appendingPathComponent(ResourceSampler.lastResourcesFileName))
        try Data(#"{"hang":"sample"}"#.utf8)
            .write(to: diagnosticsDir.appendingPathComponent("diagnostics-2026-05-23T12-00-00Z.json"))

        let receipt = try FeedbackWriter.write(
            category: .bug,
            message: "Sidebar freeze while opening /Users/example/project; prompt: \"private task\" token=sk-1234567890abcdef email alice@example.com",
            includeDiagnostics: true,
            applicationSupportRoot: tempRoot,
            bundleIdentifier: bundleId,
            now: Date(timeIntervalSince1970: 1_779_123_456)
        )

        let reportURL = receipt.url.appendingPathComponent("report.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        let data = try Data(contentsOf: reportURL)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("/Users/example"))
        XCTAssertFalse(text.contains("private task"))
        XCTAssertFalse(text.contains("sk-1234567890abcdef"))
        XCTAssertFalse(text.contains("alice@example.com"))
        XCTAssertFalse(text.contains(diagnosticsDir.path))
        XCTAssertFalse(text.contains("diagnosticsPath"))

        let report = try JSONDecoder().decode(FeedbackWriter.Report.self, from: data)
        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertEqual(report.category, FeedbackCategory.bug.rawValue)
        XCTAssertTrue(report.message.redactionApplied)
        XCTAssertFalse(report.redaction.promptsIncluded)
        XCTAssertFalse(report.redaction.secretsIncluded)
        XCTAssertFalse(report.redaction.fullLocalPathsIncluded)
        XCTAssertEqual(report.redaction.externalSubmission, "explicit_approval_only")
        XCTAssertEqual(report.diagnostics.directoryName, ClawixDiagnosticStorageRoutes.diagnosticsDirectoryName)
        XCTAssertEqual(Set(report.diagnostics.artifacts.map(\.kind)), Set(["resource.snapshot", "metrickit.diagnostics"]))
        XCTAssertTrue(report.agentHandoff.evidenceCategories.contains(DiagnosticEvidenceCategory.uiSidebar.rawValue))
        XCTAssertTrue(report.agentHandoff.evidenceCategories.contains(DiagnosticEvidenceCategory.hang.rawValue))
        XCTAssertTrue(report.agentHandoff.evidenceCategories.contains(DiagnosticEvidenceCategory.resource.rawValue))
        XCTAssertTrue(report.agentHandoff.performanceTaxonomyCategories.contains(DiagnosticEvidenceCategory.uiSidebar.rawValue))
        XCTAssertTrue(report.agentHandoff.performanceTaxonomyCategories.contains(DiagnosticEvidenceCategory.hang.rawValue))

        try? FileManager.default.removeItem(at: tempRoot)
    }
}
