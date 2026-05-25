import Foundation

enum ClawJSRuntimeLensStatusTone: String, Equatable {
    case success
    case info
    case warning
    case danger
    case muted

    static func commandDisposition(_ disposition: String) -> ClawJSRuntimeLensStatusTone {
        switch disposition {
        case "writes runtime", "blocked write":
            return .warning
        default:
            return .muted
        }
    }

    static func sessionActionStatus(_ status: String) -> ClawJSRuntimeLensStatusTone {
        switch status {
        case "implemented":
            return .success
        case "implemented_requires_confirmation", "confirmation_required", "partial":
            return .warning
        case "local_overlay_only":
            return .info
        case "blocked", "degraded":
            return .warning
        default:
            return .muted
        }
    }

    static func sessionActionDisposition(_ disposition: String) -> ClawJSRuntimeLensStatusTone {
        switch disposition {
        case "would write", "writes runtime":
            return .warning
        default:
            return .muted
        }
    }

    static func overlayConflictStatus(_ status: String) -> ClawJSRuntimeLensStatusTone {
        switch status {
        case "native_and_local":
            return .success
        case "local_only", "local_orphaned":
            return .warning
        default:
            return .info
        }
    }

    static func closureStatus(_ status: String) -> ClawJSRuntimeLensStatusTone {
        switch status {
        case "implemented_or_projected":
            return .success
        case "direct_blocker", "missing_manifest_domain_projection":
            return .danger
        case "external_pending", "product_blocked":
            return .warning
        default:
            return .info
        }
    }

    static func evidenceReentryStatus(_ status: String) -> ClawJSRuntimeLensStatusTone {
        switch status {
        case "approval_required", "blocked_until_upstream_contract":
            return .warning
        case "closed":
            return .success
        default:
            return .info
        }
    }

    static func ecosystemStage(_ stage: String) -> ClawJSRuntimeLensStatusTone {
        switch stage {
        case "production", "recommended", "native_parity":
            return .success
        case "operable", "projected":
            return .info
        case "dev_only":
            return .warning
        default:
            return .muted
        }
    }

    static func runtimeDomainStatus(
        status: String,
        supported: Bool
    ) -> ClawJSRuntimeLensStatusTone {
        switch status {
        case "ready":
            return .success
        case "degraded", "detected":
            return .warning
        case "error":
            return .danger
        case "unsupported":
            return .muted
        default:
            return supported ? .info : .muted
        }
    }

    static func supportClaim(_ claim: String) -> ClawJSRuntimeLensStatusTone {
        switch claim {
        case "operable", "projected":
            return .success
        case "inventoried":
            return .info
        case "blocked", "unsupported":
            return .muted
        default:
            return .warning
        }
    }

    static func evidenceBlockerClass(_ blockerClass: String) -> ClawJSRuntimeLensStatusTone {
        switch blockerClass {
        case "external_pending", "direct_blocker":
            return .warning
        case "lateral_debt", "pre_existing_dirty":
            return .muted
        default:
            return .info
        }
    }

    static func resourceStatus(_ status: String) -> ClawJSRuntimeLensStatusTone {
        switch status {
        case "ready", "configured", "connected", "enabled":
            return .success
        case "degraded", "disconnected", "idle":
            return .warning
        case "error", "failed":
            return .danger
        default:
            return .info
        }
    }
}
