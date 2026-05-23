import AIProviders
import XCTest
@testable import Clawix

@MainActor
final class ProviderConnectionProbeTests: XCTestCase {
    func testNewProbeCancelsStaleProviderConnectionTest() async {
        let slowStarted = expectation(description: "Slow provider probe started")
        let slowCancelled = expectation(description: "Slow provider probe cancelled")
        let fastFinished = expectation(description: "Fast provider probe finished")
        let mock = ProviderValidationMockOperation { providerId, credential, _, _ in
            if credential == "slow" {
                slowStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    slowCancelled.fulfill()
                    throw CancellationError()
                }
                return ProviderValidationReport.livePassed(providerId: providerId, apiKey: credential)
            }
            fastFinished.fulfill()
            return ProviderValidationReport.livePassed(providerId: providerId, apiKey: credential)
        }
        let probe = ProviderConnectionProbe(mode: .liveApproved, operation: mock.operation)

        probe.run(providerId: .openai, apiKey: "slow", baseURL: nil)
        await fulfillment(of: [slowStarted], timeout: 1)

        probe.run(providerId: .openai, apiKey: "fast", baseURL: nil)

        await fulfillment(of: [slowCancelled, fastFinished], timeout: 1)
        guard case .completed(let report) = probe.state else {
            return XCTFail("Expected completed provider report")
        }
        XCTAssertTrue(report.isComplete)
    }

    func testCancelStopsRunningProviderConnectionTest() async {
        let started = expectation(description: "Provider probe started")
        let cancelled = expectation(description: "Provider probe cancelled")
        let mock = ProviderValidationMockOperation { providerId, credential, _, _ in
            started.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                cancelled.fulfill()
                throw CancellationError()
            }
            return ProviderValidationReport.livePassed(providerId: providerId, apiKey: credential)
        }
        let probe = ProviderConnectionProbe(mode: .liveApproved, operation: mock.operation)

        probe.run(providerId: .openai, apiKey: "slow", baseURL: nil)
        await fulfillment(of: [started], timeout: 1)

        probe.cancel()

        await fulfillment(of: [cancelled], timeout: 1)
        XCTAssertEqual(probe.state, .idle)
    }

    func testHermeticFixtureReportsExternalPendingWithoutCompleting() async {
        let probe = ProviderConnectionProbe(
            mode: .hermeticFixture,
            operation: ProviderConnectionProbe.hermeticFixtureOperation
        )

        probe.run(providerId: .openai, apiKey: "fixture-key", baseURL: nil)

        await assertCompleted(probe) { report in
            XCTAssertEqual(report.disposition, .externalPending)
            XCTAssertEqual(report.credentialState, .placeholder)
            XCTAssertTrue(report.externalPending.contains("provider_credential_placeholder"))
            XCTAssertTrue(report.externalPending.contains("live_provider_validation_not_run"))
            XCTAssertTrue(report.evidence.contains("network_intercepted_no_provider_call"))
            XCTAssertFalse(report.isComplete)
            XCTAssertEqual(report.validationReportStatus, "EXTERNAL PENDING")
            XCTAssertEqual(report.uiStatusText, "Live validation pending")
            XCTAssertFalse(report.uiStatusText.localizedCaseInsensitiveContains("complete"))
        }
    }

    func testDefaultProbeUsesHermeticValidationAndDoesNotComplete() async {
        let probe = ProviderConnectionProbe(operation: ProviderConnectionProbe.hermeticFixtureOperation)

        probe.run(providerId: .anthropic, apiKey: "sk-ant-present-shape", baseURL: nil)

        await assertCompleted(probe) { report in
            XCTAssertEqual(report.mode, .hermeticFixture)
            XCTAssertEqual(report.disposition, .fixturePassed)
            XCTAssertEqual(report.validationReportStatus, "EXTERNAL PENDING")
            XCTAssertEqual(report.externalPending, ["live_provider_validation_not_run"])
            XCTAssertFalse(report.isComplete)
        }
    }

    func testHermeticFixtureClassifiesMissingCredentialWithoutCompleting() async {
        let probe = ProviderConnectionProbe(
            mode: .hermeticFixture,
            operation: ProviderConnectionProbe.hermeticFixtureOperation
        )

        probe.run(providerId: .openai, apiKey: "   ", baseURL: nil)

        await assertCompleted(probe) { report in
            XCTAssertEqual(report.disposition, .externalPending)
            XCTAssertEqual(report.credentialState, .missing)
            XCTAssertTrue(report.externalPending.contains("provider_credential_missing"))
            XCTAssertTrue(report.externalPending.contains("live_provider_validation_not_run"))
            XCTAssertFalse(report.isComplete)
            XCTAssertEqual(report.validationReportStatus, "EXTERNAL PENDING")
            XCTAssertFalse(report.uiStatusText.localizedCaseInsensitiveContains("complete"))
        }
    }

    func testHermeticFixtureClassifiesExpiredCredentialWithoutCompleting() async {
        let probe = ProviderConnectionProbe(
            mode: .hermeticFixture,
            operation: ProviderConnectionProbe.hermeticFixtureOperation
        )

        probe.run(
            providerId: .openai,
            apiKey: ProviderValidationFixtureInterceptor.expiredCredential,
            baseURL: nil
        )

        await assertCompleted(probe) { report in
            XCTAssertEqual(report.disposition, .externalPending)
            XCTAssertEqual(report.credentialState, .expired)
            XCTAssertTrue(report.externalPending.contains("provider_credential_expired"))
            XCTAssertTrue(report.externalPending.contains("live_provider_validation_not_run"))
            XCTAssertFalse(report.isComplete)
            XCTAssertEqual(report.validationReportStatus, "EXTERNAL PENDING")
        }
    }

    func testHermeticFixtureProviderErrorDoesNotComplete() async {
        let probe = ProviderConnectionProbe(
            mode: .hermeticFixture,
            operation: ProviderConnectionProbe.hermeticFixtureOperation
        )

        probe.run(
            providerId: .openai,
            apiKey: ProviderValidationFixtureInterceptor.providerErrorCredential,
            baseURL: nil
        )

        await assertCompleted(probe) { report in
            XCTAssertEqual(report.disposition, .providerError)
            XCTAssertEqual(report.providerError, L10n.t("Permission was denied. Review permissions, then try again."))
            XCTAssertTrue(report.externalPending.contains("live_provider_validation_not_run"))
            XCTAssertFalse(report.isComplete)
            XCTAssertEqual(report.validationReportStatus, "EXTERNAL PENDING")
            XCTAssertFalse(report.uiStatusText.localizedCaseInsensitiveContains("complete"))
        }
    }

    func testHermeticFixtureWithPresentCredentialStillRequiresLiveValidation() async {
        let probe = ProviderConnectionProbe(
            mode: .hermeticFixture,
            operation: ProviderConnectionProbe.hermeticFixtureOperation
        )

        probe.run(providerId: .anthropic, apiKey: "sk-ant-present-shape", baseURL: nil)

        await assertCompleted(probe) { report in
            XCTAssertEqual(report.disposition, .fixturePassed)
            XCTAssertEqual(report.credentialState, .present)
            XCTAssertEqual(report.externalPending, ["live_provider_validation_not_run"])
            XCTAssertFalse(report.isComplete)
            XCTAssertEqual(report.validationReportStatus, "EXTERNAL PENDING")
            XCTAssertEqual(report.uiStatusText, "Fixture only")
        }
    }

    func testHermeticValidationFixturesMatchInterceptorReports() async throws {
        for fixture in try loadHermeticValidationFixtures() {
            let providerId = try XCTUnwrap(ProviderID(rawValue: fixture.providerId), fixture.name)
            let baseURL = fixture.baseURL.flatMap(URL.init(string:))
            let report = try await ProviderValidationFixtureInterceptor.validate(
                providerId: providerId,
                apiKey: fixture.apiKey,
                baseURL: baseURL
            )

            XCTAssertEqual(report.credentialState.rawValue, fixture.credentialState, fixture.name)
            XCTAssertEqual(report.disposition.rawValue, fixture.disposition, fixture.name)
            XCTAssertEqual(report.validationReportStatus, fixture.validationReportStatus, fixture.name)
            XCTAssertEqual(report.uiStatusText, fixture.uiStatusText, fixture.name)
            XCTAssertEqual(report.isComplete, fixture.isComplete, fixture.name)
            XCTAssertEqual(report.externalPending, fixture.externalPending, fixture.name)
            XCTAssertEqual(report.providerError, fixture.providerError, fixture.name)
            XCTAssertFalse(report.uiStatusText.localizedCaseInsensitiveContains("complete"), fixture.name)
        }
    }

    private func assertCompleted(
        _ probe: ProviderConnectionProbe,
        file: StaticString = #filePath,
        line: UInt = #line,
        assertions: (ProviderValidationReport) -> Void
    ) async {
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            if case .completed(let report) = probe.state {
                assertions(report)
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Expected completed provider report", file: file, line: line)
    }

    private func loadHermeticValidationFixtures() throws -> [HermeticProviderValidationFixture] {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: "hermetic-provider-validation",
                withExtension: "json",
                subdirectory: "Fixtures/ProviderValidation"
            )
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([HermeticProviderValidationFixture].self, from: data)
    }

    private struct HermeticProviderValidationFixture: Decodable {
        let name: String
        let providerId: String
        let apiKey: String
        let baseURL: String?
        let credentialState: String
        let disposition: String
        let validationReportStatus: String
        let uiStatusText: String
        let isComplete: Bool
        let externalPending: [String]
        let providerError: String?
    }

    private struct ProviderValidationMockOperation {
        let operation: ProviderConnectionProbe.Operation

        init(operation: @escaping ProviderConnectionProbe.Operation) {
            self.operation = operation
        }
    }
}
