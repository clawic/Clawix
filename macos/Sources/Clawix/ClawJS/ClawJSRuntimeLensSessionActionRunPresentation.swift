import Foundation

struct ClawJSRuntimeLensSessionActionRunPresentation: Equatable {
    let runtime: ClawJSRuntimeLensID
    let action: String
    let requiresSession: Bool
    let requiresMessage: Bool
    let requiresTitle: Bool
    let supportsGatewayFixture: Bool
    let hasRequiredInput: Bool
    let hasLoopbackGateway: Bool
    let canCheckGate: Bool
    let canRunConfirmedFixture: Bool
    let disabledReason: String?
    let inFlight: Bool
    let actionKey: String
    let accessibilityIdentifier: String

    var accessibilityLabel: String {
        [
            "runtime session action run \(action)",
            "runtime \(runtime.rawValue)",
            "requires session \(requiresSession)",
            "requires message \(requiresMessage)",
            "requires title \(requiresTitle)",
            "gateway fixture \(supportsGatewayFixture)",
            "required input \(hasRequiredInput)",
            "loopback gateway \(hasLoopbackGateway)",
            "can check gate \(canCheckGate)",
            "can run confirmed fixture \(canRunConfirmedFixture)",
            "in flight \(inFlight)",
            disabledReason.map { "disabled \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    static func make(
        runtime: ClawJSRuntimeLensID,
        action: String,
        sessionId: String,
        message: String,
        title: String,
        gatewayURL: String,
        inFlightKeys: Set<String>
    ) -> ClawJSRuntimeLensSessionActionRunPresentation {
        let normalizedAction = action.trimmingCharacters(in: .whitespacesAndNewlines)
        let supportsGatewayFixture = runtime == .hermes && gatewayFixtureActions.contains(normalizedAction)
        let requiresSession = ["send", "inject", "abort"].contains(normalizedAction)
        let requiresMessage = ["send", "inject"].contains(normalizedAction)
        let requiresTitle = normalizedAction == "create"
        let hasRequiredInput = (!requiresSession || !trimmed(sessionId).isEmpty)
            && (!requiresMessage || !trimmed(message).isEmpty)
            && (!requiresTitle || !trimmed(title).isEmpty)
        let hasLoopbackGateway = isLoopbackGatewayURL(gatewayURL)
        let actionKey = actionKey(runtime: runtime, action: normalizedAction)
        let inFlight = inFlightKeys.contains(actionKey)
        let canCheckGate = supportsGatewayFixture && hasRequiredInput && !inFlight
        let canRunConfirmedFixture = canCheckGate && hasLoopbackGateway

        return ClawJSRuntimeLensSessionActionRunPresentation(
            runtime: runtime,
            action: normalizedAction,
            requiresSession: requiresSession,
            requiresMessage: requiresMessage,
            requiresTitle: requiresTitle,
            supportsGatewayFixture: supportsGatewayFixture,
            hasRequiredInput: hasRequiredInput,
            hasLoopbackGateway: hasLoopbackGateway,
            canCheckGate: canCheckGate,
            canRunConfirmedFixture: canRunConfirmedFixture,
            disabledReason: disabledReason(
                supportsGatewayFixture: supportsGatewayFixture,
                hasRequiredInput: hasRequiredInput,
                hasLoopbackGateway: hasLoopbackGateway,
                inFlight: inFlight
            ),
            inFlight: inFlight,
            actionKey: actionKey,
            accessibilityIdentifier: "runtime-lens-session-action-run-\(runtime.rawValue)-\(stableId(normalizedAction))"
        )
    }

    static func actionKey(runtime: ClawJSRuntimeLensID, action: String) -> String {
        "\(runtime.rawValue)::session-action::\(action)"
    }

    static func isLoopbackGatewayURL(_ value: String) -> Bool {
        guard let url = URL(string: trimmed(value)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host?.lowercased()
        else {
            return false
        }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private static let gatewayFixtureActions: Set<String> = [
        "send",
        "inject",
        "abort",
        "create"
    ]

    private static func disabledReason(
        supportsGatewayFixture: Bool,
        hasRequiredInput: Bool,
        hasLoopbackGateway: Bool,
        inFlight: Bool
    ) -> String? {
        if inFlight {
            return "action in flight"
        }
        if !supportsGatewayFixture {
            return "no fixture-backed gateway action"
        }
        if !hasRequiredInput {
            return "missing required input"
        }
        if !hasLoopbackGateway {
            return "confirmed run requires loopback gateway URL"
        }
        return nil
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stableId(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let id = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
            .lowercased()
        return id.isEmpty ? "action" : id
    }
}
