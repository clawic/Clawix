import XCTest
@testable import Clawix

final class ClawJSRemoteProjectionClientTests: XCTestCase {
    func testLoadsRemoteProjectionFromClawJSCommands() async throws {
        var captured: [[String]] = []
        let client = ClawJSRemoteProjectionClient(runner: .init { args in
            captured.append(args)
            switch args {
            case ["inspect", "remote", "--json"]:
                return .init(data: Self.inspectRemoteFixture, exitCode: 0)
            case ["remote", "contracts", "--json"]:
                return .init(data: Self.contractsFixture, exitCode: 0)
            case ["remote", "pending", "--json"]:
                return .init(data: Self.pendingFixture, exitCode: 0)
            default:
                XCTFail("unexpected args \(args)")
                return .init(data: Data(), exitCode: 1)
            }
        })

        let snapshot = try await client.load()

        XCTAssertEqual(captured, [
            ["inspect", "remote", "--json"],
            ["remote", "contracts", "--json"],
            ["remote", "pending", "--json"],
        ])
        XCTAssertEqual(snapshot.conformanceStatus, "baseline_registered")
        XCTAssertEqual(snapshot.requiredRoutes.map(\.routeId), ["remote.chatGateway", "mesh.resourceShare"])
        XCTAssertEqual(snapshot.missingRouteIds, [])
        XCTAssertEqual(snapshot.contracts.map(\.routeId), ["remote.chatGateway"])
        XCTAssertEqual(snapshot.pendingRequirements.map(\.requirementId), ["physical_iroh_handshake"])
        XCTAssertEqual(snapshot.externalPendingCount, 1)
        XCTAssertEqual(snapshot.externalValidationReadiness?.status, "not_ready")
        XCTAssertEqual(snapshot.externalValidationReadiness?.externalValidationStatus, "external_pending")
        XCTAssertEqual(snapshot.externalValidationReadiness?.blockedExternalRequirementIds, ["physical_iroh_handshake"])
        XCTAssertEqual(snapshot.closureBlockers, ["source_qa_review", "external_validation"])
        XCTAssertEqual(snapshot.providerDeviceE2EPlan?.status, "external_pending")
        XCTAssertEqual(snapshot.providerDeviceE2EPlan?.requiredDomains, ["chat"])
        XCTAssertEqual(snapshot.providerDeviceE2EPlan?.requiredRouteIds, ["remote.chatGateway"])
        XCTAssertEqual(snapshot.providerDeviceE2EPlan?.validationSteps.map(\.domain), ["chat"])
        XCTAssertEqual(snapshot.providerDeviceE2EPlan?.plaintextMaterialIncluded, false)
        XCTAssertEqual(snapshot.externalReadinessStatus, "not_ready")
        XCTAssertEqual(snapshot.closureBlockersSummary, "source_qa_review, external_validation")
        XCTAssertEqual(snapshot.blockedExternalRequirementSummary, "1 blocked")
        XCTAssertEqual(snapshot.providerDeviceE2ESummary, "1 steps / 1 domains")
        XCTAssertFalse(snapshot.writesDeclared)
        XCTAssertEqual(snapshot.sourceCommands, [
            "inspect remote --json",
            "remote contracts --json",
            "remote pending --json",
        ])
    }

    func testFailsClosedWhenProjectionCommandFails() async {
        let client = ClawJSRemoteProjectionClient(runner: .init { _ in
            .init(data: Data("missing projection".utf8), exitCode: 2)
        })

        do {
            _ = try await client.load()
            XCTFail("expected command failure")
        } catch ClawJSRemoteProjectionClient.Error.commandFailed(let command, let exitCode, let message) {
            XCTAssertEqual(command, "inspect remote --json")
            XCTAssertEqual(exitCode, 2)
            XCTAssertEqual(message, "missing projection")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testRejectsProjectionThatDeclaresWrites() async {
        let client = ClawJSRemoteProjectionClient(runner: .init { args in
            switch args {
            case ["inspect", "remote", "--json"]:
                return .init(data: Self.inspectRemoteFixture, exitCode: 0)
            case ["remote", "contracts", "--json"]:
                return .init(data: Self.contractsWithWritesFixture, exitCode: 0)
            case ["remote", "pending", "--json"]:
                return .init(data: Self.pendingFixture, exitCode: 0)
            default:
                return .init(data: Data(), exitCode: 1)
            }
        })

        do {
            _ = try await client.load()
            XCTFail("expected unsafe write rejection")
        } catch ClawJSRemoteProjectionClient.Error.unsafeWritesDeclared {
            return
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testRejectsInspectProjectionThatDeclaresWrites() async {
        let client = ClawJSRemoteProjectionClient(runner: .init { args in
            switch args {
            case ["inspect", "remote", "--json"]:
                return .init(data: Self.inspectRemoteWithWritesFixture, exitCode: 0)
            case ["remote", "contracts", "--json"]:
                return .init(data: Self.contractsFixture, exitCode: 0)
            case ["remote", "pending", "--json"]:
                return .init(data: Self.pendingFixture, exitCode: 0)
            default:
                return .init(data: Data(), exitCode: 1)
            }
        })

        do {
            _ = try await client.load()
            XCTFail("expected unsafe write rejection")
        } catch ClawJSRemoteProjectionClient.Error.unsafeWritesDeclared {
            return
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    @MainActor
    func testStorePublishesUnavailableStateInsteadOfThrowing() async {
        let store = ClawJSRemoteProjectionStore(client: ClawJSRemoteProjectionClient(runner: .init { _ in
            .init(data: Data("projection unavailable".utf8), exitCode: 2)
        }))

        store.load()
        await waitUntil {
            if case .unavailable = store.state { return true }
            return false
        }

        guard case .unavailable(let message) = store.state else {
            return XCTFail("expected unavailable state")
        }
        XCTAssertTrue(message.contains("projection unavailable"))
    }

    @MainActor
    func testStoreCancelStopsInFlightProjectionWithoutPublishingLateState() async {
        var captured: [[String]] = []
        let store = ClawJSRemoteProjectionStore(client: ClawJSRemoteProjectionClient(runner: .init { args in
            captured.append(args)
            try await Task.sleep(nanoseconds: 200_000_000)
            return .init(data: Self.inspectRemoteFixture, exitCode: 0)
        }))

        store.load()
        await waitUntil {
            if case .loading = store.state { return true }
            return false
        }
        store.cancel()

        guard case .idle = store.state else {
            return XCTFail("expected idle state after cancelling a loading projection")
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard case .idle = store.state else {
            return XCTFail("cancelled projection should not publish a late state")
        }
        XCTAssertEqual(captured, [["inspect", "remote", "--json"]])
    }

    private static let inspectRemoteFixture = Data("""
    {
      "ok": true,
      "data": {
        "schemaVersion": 1,
        "conformance": {
          "status": "baseline_registered",
          "requiredRoutes": [
            { "routeId": "remote.chatGateway", "registered": true },
            { "routeId": "mesh.resourceShare", "registered": true }
          ],
          "missingRoutes": []
        },
        "externalValidationReadiness": {
          "schemaVersion": 1,
          "status": "not_ready",
          "sourceQaReady": false,
          "sourceQaReviewStatus": "incomplete",
          "externalEvidenceReady": false,
          "externalValidationStatus": "external_pending",
          "evidenceCount": 0,
          "requiredEvidenceCount": 1,
          "missingEvidenceRequirementIds": ["physical_iroh_handshake"],
          "blockedExternalRequirementIds": ["physical_iroh_handshake"],
          "runbookReady": true,
          "checklistReady": true,
          "e2ePlanReady": true,
          "validationStepCount": 1,
          "externalRequirementCount": 1,
          "closureGateStatus": "blocked",
          "closureGateBlockers": ["source_qa_review", "external_validation"],
          "requiredCommands": ["claw remote e2e-plan --json"],
          "nextAction": "Complete source Q/A and external evidence readiness.",
          "writes": false
        },
        "providerDeviceE2EPlan": {
          "schemaVersion": 1,
          "status": "external_pending",
          "requiredDomains": ["chat"],
          "requiredTopologyTargets": ["mac_host"],
          "requiredRouteIds": ["remote.chatGateway"],
          "requiredExternalPendingIds": ["physical_iroh_handshake"],
          "validationSteps": [
            {
              "schemaVersion": 1,
              "domain": "chat",
              "requiredRouteIds": ["remote.chatGateway"],
              "requiredExternalPendingIds": ["physical_iroh_handshake"],
              "requiredArtifacts": ["remote chat gateway transcript"],
              "acceptanceCriteria": ["chat uses registered Gateway route"],
              "status": "external_pending",
              "writes": false
            }
          ],
          "evidenceRefs": ["claw inspect remote --json"],
          "approvedPhysicalValidationRequired": true,
          "noPlaintextSecrets": true,
          "plaintextMaterialIncluded": false,
          "hostedSelfHostedParityRequired": true,
          "writes": false
        }
      }
    }
    """.utf8)

    private static let inspectRemoteWithWritesFixture = Data("""
    {
      "ok": true,
      "data": {
        "schemaVersion": 1,
        "conformance": {
          "status": "baseline_registered",
          "requiredRoutes": [
            { "routeId": "remote.chatGateway", "registered": true }
          ]
        },
        "externalValidationReadiness": {
          "schemaVersion": 1,
          "status": "not_ready",
          "closureGateBlockers": ["external_validation"],
          "writes": false
        },
        "providerDeviceE2EPlan": {
          "schemaVersion": 1,
          "status": "external_pending",
          "requiredDomains": ["chat"],
          "requiredTopologyTargets": ["mac_host"],
          "requiredRouteIds": ["remote.chatGateway"],
          "requiredExternalPendingIds": ["physical_iroh_handshake"],
          "validationSteps": [
            {
              "schemaVersion": 1,
              "domain": "chat",
              "requiredRouteIds": ["remote.chatGateway"],
              "requiredExternalPendingIds": ["physical_iroh_handshake"],
              "status": "external_pending",
              "writes": true
            }
          ],
          "writes": false
        }
      }
    }
    """.utf8)

    private static let contractsFixture = Data("""
    {
      "ok": true,
      "data": {
        "schemaVersion": 1,
        "status": "complete",
        "contracts": [
          {
            "schemaVersion": 1,
            "routeId": "remote.chatGateway",
            "layer": "gateway",
            "capability": "chat sessions and conversation access",
            "parityRequired": true,
            "parallelApiAllowed": false,
            "writes": false
          }
        ],
        "missingRouteIds": [],
        "writes": false
      }
    }
    """.utf8)

    private static let contractsWithWritesFixture = Data("""
    {
      "ok": true,
      "data": {
        "schemaVersion": 1,
        "status": "complete",
        "contracts": [
          {
            "schemaVersion": 1,
            "routeId": "remote.chatGateway",
            "layer": "gateway",
            "capability": "chat sessions",
            "writes": true
          }
        ],
        "writes": true
      }
    }
    """.utf8)

    private static let pendingFixture = Data("""
    {
      "ok": true,
      "data": {
        "schemaVersion": 1,
        "status": "external_pending",
        "requirements": [
          {
            "schemaVersion": 1,
            "requirementId": "physical_iroh_handshake",
            "decisionId": "transport_contract",
            "category": "transport",
            "status": "external_pending",
            "writes": false
          }
        ],
        "writes": false
      }
    }
    """.utf8)

    private func waitUntil(
        timeout: TimeInterval = 1,
        predicate: @MainActor @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await predicate() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
