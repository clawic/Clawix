import Foundation

struct ClawJSRuntimeLensSessionOverlayActionPresentation: Equatable {
    static let localOverlayAuthority = "clawix_local_overlay"

    let runtimeId: String
    let sessionId: String
    let sessionLabel: String
    let currentPinned: Bool
    let targetPinned: Bool
    let action: String
    let buttonTitle: String
    let systemImage: String
    let helpText: String
    let actionKey: String
    let disabled: Bool
    let inFlight: Bool
    let writesRuntime: Bool
    let authority: String
    let accessibilityIdentifier: String

    var accessibilityLabel: String {
        [
            "runtime session overlay action \(action)",
            "runtime \(runtimeId)",
            "session \(sessionLabel)",
            "current pinned \(currentPinned)",
            "target pinned \(targetPinned)",
            "writes runtime \(writesRuntime)",
            "authority \(authority)",
            "in flight \(inFlight)",
            "disabled \(disabled)"
        ]
        .joined(separator: ", ")
    }

    static func make(
        snapshot: ClawJSRuntimeLensSnapshot,
        resource: ClawJSRuntimeLensSnapshot.RuntimeResource,
        inFlightKeys: Set<String>
    ) -> ClawJSRuntimeLensSessionOverlayActionPresentation {
        let currentPinned = resource.pinned == true
        let action = currentPinned ? "unpin" : "pin"
        let actionKey = actionKey(runtimeId: snapshot.runtimeId, sessionId: resource.id)
        let inFlight = inFlightKeys.contains(actionKey)
        let runtimeKnown = ClawJSRuntimeLensID(rawValue: snapshot.runtimeId) != nil
        let sessionLabel = normalized(resource.displayLabel) ?? resource.id

        return ClawJSRuntimeLensSessionOverlayActionPresentation(
            runtimeId: snapshot.runtimeId,
            sessionId: resource.id,
            sessionLabel: sessionLabel,
            currentPinned: currentPinned,
            targetPinned: !currentPinned,
            action: action,
            buttonTitle: currentPinned ? "Unpin" : "Pin",
            systemImage: currentPinned ? "pin.slash" : "pin",
            helpText: currentPinned ? "Remove local runtime pin" : "Add local runtime pin",
            actionKey: actionKey,
            disabled: inFlight || !runtimeKnown,
            inFlight: inFlight,
            writesRuntime: false,
            authority: localOverlayAuthority,
            accessibilityIdentifier: "runtime-lens-session-overlay-action-\(snapshot.runtimeId)-\(stableId(resource.id))"
        )
    }

    static func actionKey(runtimeId: String, sessionId: String) -> String {
        "\(runtimeId)::\(sessionId)"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        return value
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
        return id.isEmpty ? "session" : id
    }
}
