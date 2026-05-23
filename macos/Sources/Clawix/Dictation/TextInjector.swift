import Foundation

/// Routes dictation text insertion through the central macOS action broker.
///
/// The broker owns the native execution details: pasteboard snapshot/restore,
/// synthesized paste, optional auto-send, AX permission declaration, approval,
/// and audit. Clawix keeps only dictation-specific validation and request
/// construction here so executable host behavior has a single policy choke
/// point.
@MainActor
enum TextInjector {

    enum InjectError: Error, LocalizedError {
        case accessibilityNotGranted
        case brokerFailed(String)
        case empty

        var errorDescription: String? {
            switch self {
            case .accessibilityNotGranted:
                return "Allow Clawix in Accessibility to paste transcripts"
            case .brokerFailed(let reason):
                return reason
            case .empty:
                return "Empty transcript"
            }
        }
    }

    static func inject(
        text: String,
        restorePrevious: Bool = true,
        autoSendKey: DictationAutoSendKey = .none,
        restoreAfter: TimeInterval = 1.5,
        addSpaceBefore: Bool = false,
        runner: NativeMacActionCommandRunning = NativeMacActionProcessRunner(),
        auditURL: URL? = nil,
        permissionStatus: NativeMacPermissionBroker.Status? = nil
    ) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw InjectError.empty }
        if let capturePath = ProcessInfo.processInfo.environment["CLAWIX_E2E_TEXT_INJECTOR_CAPTURE"] {
            try injectForE2E(
                text: text,
                restorePrevious: restorePrevious,
                autoSendKey: autoSendKey,
                restoreAfter: restoreAfter,
                capturePath: capturePath,
                addSpaceBefore: addSpaceBefore
            )
            return
        }
        let resolvedPermissionStatus = permissionStatus
            ?? NativeMacPermissionBroker.status(for: .accessibility)
        guard resolvedPermissionStatus == .granted else {
            throw InjectError.accessibilityNotGranted
        }

        let receipt = NativeMacActionBroker.evaluate(
            NativeMacActionRequest(
                capabilityId: "mac.text.inject",
                actorId: "clawix.dictation",
                origin: .userUI,
                actorKind: "user_ui",
                arguments: [
                    "text": text,
                    "restorePrevious": String(restorePrevious),
                    "autoSend": autoSendKey.brokerArgument,
                    "restoreAfter": String(restoreAfter),
                    "addSpaceBefore": String(addSpaceBefore),
                ]
            ),
            auditURL: auditURL,
            runner: runner
        )
        guard receipt.outcome == .executed else {
            throw InjectError.brokerFailed(
                receipt.error ?? "Dictation text injection did not execute."
            )
        }
    }

    private static func injectForE2E(
        text: String,
        restorePrevious: Bool,
        autoSendKey: DictationAutoSendKey,
        restoreAfter: TimeInterval,
        capturePath: String,
        addSpaceBefore: Bool
    ) throws {
        let report: [String: Any] = [
            "payload": text,
            "payloadLength": text.count,
            "restorePrevious": restorePrevious,
            "restoreAfter": restoreAfter,
            "autoSendKey": autoSendKey.rawValue,
            "brokerAutoSend": autoSendKey.brokerArgument,
            "addSpaceBefore": addSpaceBefore,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: capturePath), options: .atomic)
    }
}

private extension DictationAutoSendKey {
    var brokerArgument: String {
        switch self {
        case .none:
            return "none"
        case .enter:
            return "enter"
        case .shiftEnter:
            return "shift_enter"
        case .cmdEnter:
            return "cmd_enter"
        }
    }
}
