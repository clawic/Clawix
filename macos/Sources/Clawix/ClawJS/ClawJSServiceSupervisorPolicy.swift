import Foundation

enum ClawJSServiceSupervisorPolicy {
    static let restartBudget = 5
    static let backoffSchedule: [UInt64] = [1, 2, 4, 8, 16, 32, 60]
    static let healthyResetWindow: TimeInterval = 60

    static let adminTokenEnvVar: [ClawJSService: String] = [
        .runtime: "RUNTIME_SHARED_SECRET",
        .database: "CLAW_DATABASE_ADMIN_TOKEN",
        .drive: "CLAW_DRIVE_ADMIN_TOKEN",
        .secrets: "CLAW_SECRETS_ADMIN_TOKEN",
        .audio: "CLAW_AUDIO_SHARED_SECRET",
        .index: "CLAW_SEARCH_ADMIN_TOKEN",
        .sessions: "CLAW_SESSIONS_SHARED_SECRET",
        .publishing: "CLAW_PUBLISHING_TOKEN",
    ]

    static func requiresSessionAdminToken(_ service: ClawJSService) -> Bool {
        adminTokenEnvVar[service] != nil
    }

    static func canAdoptExistingService(_ service: ClawJSService) -> Bool {
        !requiresSessionAdminToken(service)
    }

    static func availableOnDemandState(for service: ClawJSService) -> ClawJSServiceState {
        .availableOnDemand(trigger: ClawJSServiceDemandPolicy.onDemandTrigger(for: service) ?? service.rawValue)
    }

    static func restartDelay(for restartCount: Int) -> UInt64 {
        backoffSchedule[min(restartCount, backoffSchedule.count - 1)]
    }
}
