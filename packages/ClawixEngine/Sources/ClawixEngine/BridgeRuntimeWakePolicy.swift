import Foundation
import ClawixCore

enum BridgeRuntimeWakePolicy {
    static func reason(for body: BridgeBody) -> String? {
        switch body {
        case .openSession:
            return "openSession"
        case .sendMessage:
            return "sendMessage"
        case .newSession:
            return "newSession"
        case .interruptTurn:
            return "interruptTurn"
        case .editPrompt:
            return "editPrompt"
        case .archiveSession, .unarchiveSession:
            return "archiveSession"
        case .renameSession:
            return "renameSession"
        default:
            return nil
        }
    }
}

@MainActor
public final class BridgeRuntimeStartGate {
    private var task: Task<Void, Error>?
    private var didStart = false

    public init() {}

    public func ensureStarted(
        reason: String,
        start: @MainActor @escaping (_ reason: String) async throws -> Void
    ) async throws {
        if didStart { return }
        if let task {
            try await task.value
            return
        }

        let task = Task { @MainActor in
            try await start(reason)
        }
        self.task = task
        do {
            try await task.value
            didStart = true
        } catch {
            self.task = nil
            throw error
        }
    }
}
