import XCTest
@testable import Clawix

@MainActor
final class ClawJSSecretsMapperFailClosedTests: XCTestCase {
    private let folderId = "11111111-1111-1111-1111-111111111111"
    private let secretId = "22222222-2222-2222-2222-222222222222"
    private let grantId = "33333333-3333-3333-3333-333333333333"
    private let timestamp = "2026-05-21T10:00:00.000Z"

    func testInvalidSecretIdFailsClosed() {
        var secret = validSecret()
        secret = secret.with(id: "not-a-uuid")

        assertInvalidResponse {
            _ = try ClawJSMapper.mapDescribedSecret(secret)
        }
    }

    func testInvalidFolderIdFailsClosed() {
        var secret = validSecret()
        secret = secret.with(folderId: "not-a-uuid")

        assertInvalidResponse {
            _ = try ClawJSMapper.mapDescribedSecret(secret)
        }
    }

    func testUnknownSecretKindFailsClosed() {
        var secret = validSecret()
        secret = secret.with(typeId: "custom")

        assertInvalidResponse {
            _ = try ClawJSMapper.mapDescribedSecret(secret)
        }
    }

    func testUnknownAuditKindFailsClosed() {
        var event = validAuditEvent()
        event = event.with(kind: "custom_audit_event")

        assertInvalidResponse {
            _ = try ClawJSMapper.mapAuditEvent(event)
        }
    }

    func testUnknownGrantCapabilityFailsClosed() {
        var grant = validGrant()
        grant = grant.with(capability: ["kind": Clawix.AnyCodable("custom")])

        assertInvalidResponse {
            _ = try ClawJSMapper.mapGrantSummary(grant)
        }
    }

    private func validSecret() -> ClawJSSecretsClient.DescribedSecret {
        ClawJSSecretsClient.DescribedSecret(
            id: secretId,
            tenantId: "clawix-local",
            folderId: folderId,
            typeId: "api_key",
            internalName: "github-token",
            title: "GitHub token",
            versionNumber: 1,
            versionReason: "create",
            governance: .init(
                allowedHosts: [],
                allowedHeaders: [],
                allowInUrl: false,
                allowInBody: false,
                allowInEnv: true,
                allowInsecureTransport: false,
                allowLocalNetwork: false,
                allowedAgents: nil,
                approvalMode: "auto",
                approvalWindowMinutes: nil,
                ttlExpiresAt: nil,
                maxUses: nil,
                rotationReminderDays: nil,
                redactionLabel: nil,
                clipboardClearSeconds: nil,
                auditRetentionDays: nil,
                requiresVpn: false,
                vpnProfileName: nil
            ),
            states: .init(
                isArchived: false,
                isCompromised: false,
                isCompromisedReason: nil,
                isLocked: false,
                readOnly: false,
                trashedAt: nil
            ),
            counters: .init(useCount: 0, lastUsedAt: nil, lastRotatedAt: nil),
            tags: [],
            fields: [],
            hasNotes: false,
            attachments: [],
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }

    private func validAuditEvent() -> ClawJSSecretsClient.AuditEvent {
        ClawJSSecretsClient.AuditEvent(
            id: grantId,
            tenantId: "clawix-local",
            secretId: secretId,
            kind: "grant_issued",
            timestamp: timestamp,
            source: "system",
            success: true,
            sequence: 1,
            prevHashBase64: "",
            selfHashBase64: "",
            payload: [:]
        )
    }

    private func validGrant() -> ClawJSSecretsClient.AgentGrantSummary {
        ClawJSSecretsClient.AgentGrantSummary(
            id: grantId,
            tenantId: "clawix-local",
            agent: "agent.test",
            secretId: secretId,
            capability: ["kind": Clawix.AnyCodable("github_git_push")],
            secretsCapabilities: [],
            reason: "test",
            createdAt: timestamp,
            expiresAt: "2026-05-21T10:10:00.000Z",
            revokedAt: nil,
            usedCount: 0,
            lastUsedAt: nil
        )
    }

    private func assertInvalidResponse(_ body: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            guard case ClawJSBackendError.invalidResponse = error else {
                XCTFail("Expected invalidResponse, got \(error)", file: file, line: line)
                return
            }
        }
    }
}

private extension ClawJSSecretsClient.DescribedSecret {
    func with(id: String? = nil, folderId: String? = nil, typeId: String? = nil) -> Self {
        .init(
            id: id ?? self.id,
            tenantId: tenantId,
            folderId: folderId ?? self.folderId,
            typeId: typeId ?? self.typeId,
            internalName: internalName,
            title: title,
            versionNumber: versionNumber,
            versionReason: versionReason,
            governance: governance,
            states: states,
            counters: counters,
            tags: tags,
            fields: fields,
            hasNotes: hasNotes,
            attachments: attachments,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private extension ClawJSSecretsClient.AuditEvent {
    func with(kind: String) -> Self {
        .init(
            id: id,
            tenantId: tenantId,
            secretId: secretId,
            kind: kind,
            timestamp: timestamp,
            source: source,
            success: success,
            sequence: sequence,
            prevHashBase64: prevHashBase64,
            selfHashBase64: selfHashBase64,
            payload: payload
        )
    }
}

private extension ClawJSSecretsClient.AgentGrantSummary {
    func with(capability: [String: Clawix.AnyCodable]) -> Self {
        .init(
            id: id,
            tenantId: tenantId,
            agent: agent,
            secretId: secretId,
            capability: capability,
            secretsCapabilities: secretsCapabilities,
            reason: reason,
            createdAt: createdAt,
            expiresAt: expiresAt,
            revokedAt: revokedAt,
            usedCount: usedCount,
            lastUsedAt: lastUsedAt
        )
    }
}
