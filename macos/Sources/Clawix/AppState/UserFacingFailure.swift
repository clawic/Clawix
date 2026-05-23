import Foundation
import OSLog

enum UserFacingFailureKind: String, Equatable {
    case backendUnavailable
    case daemonUnavailable
    case permissionDenied
    case modelUnavailable
    case networkOffline
    case serviceUnavailable
    case unknown
}

struct UserFacingFailure: Equatable {
    let kind: UserFacingFailureKind
    let rawMessage: String
    let retryable: Bool

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.example.clawix",
        category: "failure"
    )

    static func classify(_ message: String) -> UserFacingFailure {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if containsAny(lower, [
            "not connected to the internet",
            "internet connection appears to be offline",
            "network connection lost",
            "cannot connect to host",
            "cannot find host",
            "timed out",
            "offline"
        ]) {
            return UserFacingFailure(kind: .networkOffline, rawMessage: trimmed, retryable: true)
        }

        if containsAny(lower, [
            "permission denied",
            "permissions were denied",
            "permission was denied",
            "workspace is denied",
            "workspacedenied",
            "not authorized",
            "unauthorized"
        ]) {
            return UserFacingFailure(kind: .permissionDenied, rawMessage: trimmed, retryable: true)
        }

        if containsAny(lower, [
            "model unavailable",
            "model is unavailable",
            "model not found",
            "unknown model",
            "not downloaded",
            "download a model",
            "no such model"
        ]) {
            return UserFacingFailure(kind: .modelUnavailable, rawMessage: trimmed, retryable: true)
        }

        if containsAny(lower, [
            "background bridge",
            "bridge is not ready",
            "daemonunreachable",
            "daemon unreachable",
            "daemon is unavailable",
            "reconnects",
            "reconnecting"
        ]) {
            return UserFacingFailure(kind: .daemonUnavailable, rawMessage: trimmed, retryable: true)
        }

        if containsAny(lower, [
            "backend binary not found",
            "backend app-server failed",
            "clawix backend is not running",
            "agent runtime is unavailable",
            "runtime is unavailable",
            "backend not ready"
        ]) {
            return UserFacingFailure(kind: .backendUnavailable, rawMessage: trimmed, retryable: true)
        }

        if containsAny(lower, [
            "service is unavailable",
            "service unavailable",
            "servicenotready",
            "service not ready",
            "could not reach"
        ]) {
            return UserFacingFailure(kind: .serviceUnavailable, rawMessage: trimmed, retryable: true)
        }

        return UserFacingFailure(kind: .unknown, rawMessage: trimmed, retryable: true)
    }

    var displayMessage: String {
        switch kind {
        case .backendUnavailable:
            return L10n.t("The agent runtime is unavailable. Try again after it reconnects.")
        case .daemonUnavailable:
            return L10n.t("The background bridge is unavailable. Try again after it reconnects.")
        case .permissionDenied:
            return L10n.t("Permission was denied. Review permissions, then try again.")
        case .modelUnavailable:
            return L10n.t("That model is not available. Pick another model and try again.")
        case .networkOffline:
            return L10n.t("The network appears to be offline. Reconnect, then try again.")
        case .serviceUnavailable:
            return L10n.t("The service is unavailable. Try again in a moment.")
        case .unknown:
            return rawMessage.isEmpty ? L10n.t("Request failed. Try again in a moment.") : rawMessage
        }
    }

    var chatLine: String {
        String(format: L10n.t("Error: %@"), displayMessage)
    }

    func log(surface: String) {
        Self.logger.warning(
            "failure surface=\(surface, privacy: .public) kind=\(kind.rawValue, privacy: .public) retryable=\(retryable, privacy: .public) detail=\(rawMessage, privacy: .private)"
        )
    }

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}
