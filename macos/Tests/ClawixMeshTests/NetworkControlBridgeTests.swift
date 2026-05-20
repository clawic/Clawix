import ClawHostKit
import XCTest
@testable import Clawix

final class NetworkControlBridgeTests: XCTestCase {
    func testDecodesNetworkStatusAdaptersRulesAndEvents() throws {
        let status = try NetworkControlBridge.decodeStatus(CommandResponse(
            ok: true,
            data: .object([
                "privacy": .object([
                    "detailOptIn": .bool(false),
                    "defaultRedaction": .string("aggregate"),
                ]),
                "enforcement": .object([
                    "clawRuntime": .string("ready"),
                    "gateway": .string("ready"),
                    "nativeMac": .string("external_pending"),
                ]),
                "monitor": .object([
                    "recentEvents": .integer(2),
                    "dbPath": .string("/tmp/monitor.sqlite"),
                ]),
            ]),
            error: nil,
            meta: .init(adapter: "network-control", source: .framework, durationMS: 0)
        ))

        XCTAssertEqual(status.defaultRedaction, "aggregate")
        XCTAssertEqual(status.gateway, "ready")
        XCTAssertEqual(status.nativeMac, "external_pending")
        XCTAssertEqual(status.recentEvents, 2)

        let adapters = try NetworkControlBridge.decodeAdapters(CommandResponse(
            ok: true,
            data: .object([
                "adapters": .array([
                    .object([
                        "id": .string("network.adapter.gateway"),
                        "kind": .string("gateway"),
                        "label": .string("Gateway routes"),
                        "status": .string("ready"),
                        "enforcement": .string("enforce"),
                        "externalPending": .bool(false),
                        "reason": .string("Gateway route checks can evaluate shared policy."),
                    ]),
                    .object([
                        "id": .string("network.adapter.macContentFilter"),
                        "kind": .string("macContentFilter"),
                        "label": .string("macOS content filter"),
                        "status": .string("external_pending"),
                        "enforcement": .string("plan_only"),
                        "externalPending": .bool(true),
                        "reason": .string("Requires entitlement."),
                        "reentryCondition": .string("Approved signed-host validation."),
                    ]),
                ]),
            ]),
            error: nil,
            meta: .init(adapter: "network-control", source: .framework, durationMS: 0)
        ))

        XCTAssertEqual(adapters.count, 2)
        XCTAssertEqual(adapters[0].kind, "gateway")
        XCTAssertEqual(adapters[1].externalPending, true)
        XCTAssertEqual(adapters[1].reentryCondition, "Approved signed-host validation.")

        let rules = try NetworkControlBridge.decodeRules(CommandResponse(
            ok: true,
            data: .object([
                "rules": .array([
                    .object([
                        "id": .string("network.rule.deny.search"),
                        "action": .string("deny"),
                        "subject": .object(["kind": .string("gateway")]),
                        "endpoint": .object([
                            "kind": .string("gateway_route"),
                            "value": .string("remote.searchGateway"),
                        ]),
                        "priority": .integer(200),
                        "enabled": .bool(true),
                        "source": .string("human"),
                    ]),
                ]),
            ]),
            error: nil,
            meta: .init(adapter: "network-control", source: .framework, durationMS: 0)
        ))

        XCTAssertEqual(rules.first?.id, "network.rule.deny.search")
        XCTAssertEqual(rules.first?.endpointValue, "remote.searchGateway")

        let events = try NetworkControlBridge.decodeEvents(CommandResponse(
            ok: true,
            data: .object([
                "events": .array([
                    .object([
                        "id": .string("evt_gateway"),
                        "observedAt": .string("2026-05-20T00:00:00.000Z"),
                        "subject": .object([
                            "kind": .string("gateway"),
                            "id": .string("gateway.agent.ops"),
                        ]),
                        "endpoint": .object([
                            "kind": .string("gateway_route"),
                            "value": .string("gateway_route"),
                        ]),
                        "decision": .string("allow"),
                        "adapterId": .string("network.adapter.gateway"),
                        "bytesIn": .integer(10),
                        "bytesOut": .integer(20),
                        "redaction": .object([
                            "domainHidden": .bool(true),
                            "processHidden": .bool(true),
                        ]),
                    ]),
                ]),
            ]),
            error: nil,
            meta: .init(adapter: "network-control", source: .framework, durationMS: 0)
        ))

        XCTAssertEqual(events.first?.endpointValue, "gateway_route")
        XCTAssertEqual(events.first?.domainHidden, true)
    }

    func testDecodesGatewayRouteDecision() throws {
        let route = try NetworkControlBridge.decodeRouteDecision(CommandResponse(
            ok: true,
            data: .object([
                "routes": .array([
                    .object([
                        "routeId": .string("remote.chatGateway"),
                        "adapterId": .string("network.adapter.gateway"),
                        "enforcement": .string("allowed"),
                        "policy": .object([
                            "decision": .string("allow"),
                            "adapterId": .string("network.adapter.gateway"),
                            "explanation": .string("Matched network.rule.claw-gateway-known-routes: allow."),
                            "matchedRuleIds": .array([
                                .string("network.rule.claw-gateway-known-routes"),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
            error: nil,
            meta: .init(adapter: "network-control", source: .framework, durationMS: 0)
        ))

        XCTAssertEqual(route.routeID, "remote.chatGateway")
        XCTAssertEqual(route.decision, "allow")
        XCTAssertEqual(route.adapterID, "network.adapter.gateway")
        XCTAssertEqual(route.matchedRuleIDs, ["network.rule.claw-gateway-known-routes"])
        XCTAssertEqual(route.enforcement, "allowed")
    }

    func testBridgeUsesSystemNetworkResourceWithoutNativeMutation() async throws {
        var captured: CommandRequest?
        let bridge = NetworkControlBridge { request in
            captured = request
            return CommandResponse(
                ok: true,
                data: .object([
                    "privacy": .object([
                        "detailOptIn": .bool(true),
                        "defaultRedaction": .string("process_domain_opt_in"),
                    ]),
                    "enforcement": .object([
                        "clawRuntime": .string("ready"),
                        "gateway": .string("ready"),
                        "nativeMac": .string("external_pending"),
                    ]),
                    "monitor": .object(["recentEvents": .integer(0)]),
                ]),
                error: nil,
                meta: .init(adapter: "network-control", source: .framework, durationMS: 0)
            )
        }

        let status = try await bridge.status(detailOptIn: true)

        XCTAssertEqual(status.detailOptIn, true)
        XCTAssertEqual(captured?.domain, .system)
        XCTAssertEqual(captured?.resource, "network")
        XCTAssertEqual(captured?.action, "status")
        XCTAssertEqual(captured?.arguments["detail_opt_in"], "true")
    }
}
