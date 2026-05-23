import Foundation

enum HostActionSurface: String, Codable, CaseIterable {
    case screenTools
    case macUtilities
    case macControl

    var gateSurfaceId: String {
        switch self {
        case .screenTools:
            return "screen-tools"
        case .macUtilities:
            return "mac-utilities"
        case .macControl:
            return "mac-control"
        }
    }

    var approvalKey: String {
        switch self {
        case .screenTools:
            return HostActionPolicy.screenToolsApprovalKey
        case .macUtilities:
            return HostActionPolicy.macUtilitiesApprovalKey
        case .macControl:
            return HostActionPolicy.macControlApprovalKey
        }
    }
}

enum HostActionOrigin: String, Codable {
    case userInterface
    case appIntent
    case agent
    case framework

    var isUserApproved: Bool {
        switch self {
        case .userInterface, .appIntent:
            return true
        case .agent, .framework:
            return false
        }
    }
}

enum HostActionPolicy {
    enum Approval: String, Codable, CaseIterable {
        case alwaysAsk
        case alwaysAllow
        case alwaysBlock
    }

    enum Risk: String, Codable, CaseIterable {
        case read
        case low
        case medium
        case high
        case critical
    }

    struct Authorization: Equatable {
        let allowed: Bool
        let outcome: String
        let reason: String?
        let planId: String
        let receiptId: String?
        let auditId: String
        let risk: Risk
    }

    struct RollbackPlan: Codable, Equatable {
        let level: String
        let refs: [String]
        let timerSeconds: Int?
        let humanRequired: Bool
    }

    struct Redaction: Codable, Equatable {
        let fields: [String]
        let policy: String
    }

    struct AuditEvent: Codable, Equatable {
        let schemaVersion: Int
        let auditId: String
        let timestamp: String
        let planId: String
        let receiptId: String?
        let surfaceId: String
        let surface: HostActionSurface
        let capabilityId: String
        let action: String
        let origin: HostActionOrigin
        let approval: Approval
        let risk: Risk
        let decision: String
        let outcome: String
        let reason: String?
        let rollback: RollbackPlan
        let redaction: Redaction
    }

    static let schemaVersion = 1
    static let screenToolsApprovalKey = "clawix.hostPolicy.screenTools.approval"
    static let macUtilitiesApprovalKey = "clawix.hostPolicy.macUtilities.approval"
    static let macControlApprovalKey = "clawix.hostPolicy.macControl.approval"
    static let auditFilename = ClawixPersistentSurfacePaths.components.hostActionAuditFile

    static func approval(
        for surface: HostActionSurface,
        defaults: UserDefaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
    ) -> Approval {
        guard let raw = defaults.string(forKey: surface.approvalKey),
              let approval = Approval(rawValue: raw) else {
            return .alwaysAsk
        }
        return approval
    }

    @discardableResult
    static func authorize(
        surface: HostActionSurface,
        action: String,
        origin: HostActionOrigin,
        defaults: UserDefaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard,
        auditURL: URL? = nil,
        now: Date = Date(),
        approvedOverride: Bool = false
    ) -> Authorization {
        let policy = approval(for: surface, defaults: defaults)
        let risk = gateRisk(surface: surface, action: action)
        let planId = "gate_plan_\(UUID().uuidString.lowercased())"
        let receiptId: String?
        let auditId = "gate_audit_\(UUID().uuidString.lowercased())"
        let authorization: Authorization
        switch policy {
        case .alwaysAllow:
            receiptId = "gate_receipt_\(UUID().uuidString.lowercased())"
            authorization = Authorization(allowed: true, outcome: "allowed", reason: nil, planId: planId, receiptId: receiptId, auditId: auditId, risk: risk)
        case .alwaysBlock:
            receiptId = nil
            authorization = Authorization(allowed: false, outcome: "blocked", reason: "Host policy blocks this action.", planId: planId, receiptId: receiptId, auditId: auditId, risk: risk)
        case .alwaysAsk:
            if approvedOverride {
                receiptId = "gate_receipt_\(UUID().uuidString.lowercased())"
                authorization = Authorization(allowed: true, outcome: "approved", reason: nil, planId: planId, receiptId: receiptId, auditId: auditId, risk: risk)
            } else if origin.isUserApproved {
                receiptId = "gate_receipt_\(UUID().uuidString.lowercased())"
                authorization = Authorization(allowed: true, outcome: "allowed", reason: nil, planId: planId, receiptId: receiptId, auditId: auditId, risk: risk)
            } else {
                receiptId = nil
                authorization = Authorization(
                    allowed: false,
                    outcome: "requiresApproval",
                    reason: "Requires explicit host approval.",
                    planId: planId,
                    receiptId: receiptId,
                    auditId: auditId,
                    risk: risk
                )
            }
        }

        appendAudit(
            AuditEvent(
                schemaVersion: schemaVersion,
                auditId: auditId,
                timestamp: Self.timestampFormatter.string(from: now),
                planId: planId,
                receiptId: receiptId,
                surfaceId: surface.gateSurfaceId,
                surface: surface,
                capabilityId: "\(surface.gateSurfaceId).\(action)",
                action: action,
                origin: origin,
                approval: policy,
                risk: risk,
                decision: gateDecision(for: authorization.outcome),
                outcome: authorization.outcome,
                reason: authorization.reason,
                rollback: rollbackPlan(surface: surface, action: action, allowed: authorization.allowed),
                redaction: redaction(surface: surface)
            ),
            to: auditURL ?? defaultAuditURL()
        )
        return authorization
    }

    private static func defaultAuditURL() -> URL {
        ClawixHostActionRoutes.hostActionAuditURL()
    }

    private static func appendAudit(_ event: AuditEvent, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            var data = try encoder.encode(event)
            data.append(0x0A)
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            // Audit failures must not execute the action silently. The caller
            // still receives the policy decision, and diagnostics carry the
            // audit write problem for local investigation.
            NSLog("Clawix host action audit write failed: \(error.localizedDescription)")
        }
    }

    private static func gateRisk(surface: HostActionSurface, action: String) -> Risk {
        switch surface {
        case .screenTools:
            if action == "openCaptureHistory" || action.hasPrefix("reveal") || action.hasPrefix("open") {
                return .medium
            }
            return .high
        case .macUtilities:
            switch action {
            case "clearClipboard", "sleepDisplays", "toggleDesktopIcons", "toggleKeepAwake":
                return .high
            case "hideAllWindows", "minimizeAllWindows", "minimizeAllWindowsExceptFrontmost", "minimizeAppWindowsExceptFrontmost", "isolateWindow", "unminimizeAllWindows", "showDesktop", "toggleDarkMode", "toggleMuteSound":
                return .medium
            default:
                return .low
            }
        case .macControl:
            return .high
        }
    }

    private static func gateDecision(for outcome: String) -> String {
        switch outcome {
        case "allowed", "approved":
            return "allow"
        case "blocked":
            return "blocked"
        case "requiresApproval":
            return "requires_approval"
        default:
            return outcome
        }
    }

    private static func rollbackPlan(surface: HostActionSurface, action: String, allowed: Bool) -> RollbackPlan {
        let refs = [
            "\(surface.gateSurfaceId).\(action)",
            allowed ? "receipt_required_for_execution" : "no_execution_receipt"
        ]
        switch surface {
        case .screenTools:
            return RollbackPlan(level: "best_effort", refs: refs, timerSeconds: nil, humanRequired: true)
        case .macUtilities:
            switch action {
            case "toggleDarkMode", "toggleMuteSound", "toggleKeepAwake", "toggleDesktopIcons":
                return RollbackPlan(level: "best_effort", refs: refs, timerSeconds: nil, humanRequired: false)
            default:
                return RollbackPlan(level: "none", refs: refs, timerSeconds: nil, humanRequired: true)
            }
        case .macControl:
            return RollbackPlan(level: "best_effort", refs: refs, timerSeconds: 120, humanRequired: true)
        }
    }

    private static func redaction(surface: HostActionSurface) -> Redaction {
        switch surface {
        case .screenTools:
            return Redaction(fields: ["path", "image", "ocrText", "screenContent"], policy: "host_action_gate_v1")
        case .macUtilities:
            return Redaction(fields: ["processOutput", "clipboard", "windowTitle"], policy: "host_action_gate_v1")
        case .macControl:
            return Redaction(fields: ["arguments", "stdout", "stderr", "secretRef"], policy: "host_action_gate_v1")
        }
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
