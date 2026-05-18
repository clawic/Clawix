import Foundation

struct MacControlGlobalInboxProjection {
    let approvalRecordId: String
    let inboxThreadId: String
    let inboxMessageId: String
}

@MainActor
protocol MacControlGlobalInboxWriting {
    func createRecord(collection name: String, data: [String: DBJSON]) async throws -> DBRecord
    func deleteRecord(collection name: String, id: String) async throws
}

extension DatabaseManager: MacControlGlobalInboxWriting {}

@MainActor
enum MacControlGlobalInboxProjector {
    static func project(
        _ approval: MacControlPendingApproval,
        using writer: MacControlGlobalInboxWriting
    ) async throws -> MacControlGlobalInboxProjection {
        let title = "Mac Control approval: \(approval.capabilityId)"
        let content = """
        Approval required for \(approval.capabilityId)
        Risk: \(approval.risk)
        Roles: \(approval.approverRoles.joined(separator: ", "))
        Reason: \(approval.reason)
        Request: \(approval.requestId)
        """
        let createdAt = ISO8601DateFormatter().string(from: approval.createdAt)
        let evidence: DBJSON = .array([
            .string(approval.id),
            .string(approval.requestId),
            .string(approval.capabilityId),
        ])

        let approvalRecord = try await writer.createRecord(collection: "approvals", data: [
            "title": .string(title),
            "status": .string("pending"),
            "kind": .string("policy_gate"),
            "requestedByAgentId": .string("clawix_settings"),
            "policyReason": .string(approval.reason),
            "evidenceIds": evidence,
            "confidence": .number(1.0),
        ])

        do {
            let thread = try await writer.createRecord(collection: "inbox_threads", data: [
                "channel": .string("mac_control"),
                "status": .string("unread"),
                "subject": .string(title),
                "externalThreadId": .string(approval.id),
                "latestMessageAt": .string(createdAt),
                "preview": .string(approval.reason),
            ])

            do {
                let message = try await writer.createRecord(collection: "inbox_messages", data: [
                    "threadId": .string(thread.id),
                    "channel": .string("mac_control"),
                    "externalThreadId": .string(approval.id),
                    "externalMessageId": .string(approval.requestId),
                    "direction": .string("system"),
                    "status": .string("unread"),
                    "attachments": .object([
                        "approvalRecordId": .string(approvalRecord.id),
                        "capabilityId": .string(approval.capabilityId),
                    ]),
                    "content": .string(content),
                ])
                return MacControlGlobalInboxProjection(
                    approvalRecordId: approvalRecord.id,
                    inboxThreadId: thread.id,
                    inboxMessageId: message.id
                )
            } catch {
                try? await writer.deleteRecord(collection: "inbox_threads", id: thread.id)
                try? await writer.deleteRecord(collection: "approvals", id: approvalRecord.id)
                throw error
            }
        } catch {
            try? await writer.deleteRecord(collection: "approvals", id: approvalRecord.id)
            throw error
        }
    }
}
