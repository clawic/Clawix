import Foundation

struct ClawJSRuntimeLensSessionDescriptorPresentation: Equatable {
    let primaryTransport: String
    let transportKind: String?
    let streaming: Bool
    let streamingLabel: String?
    let persistence: String?
    let fallbackTransport: String?
    let sessionPath: String?
    let hasFallback: Bool
    let hasPath: Bool

    var transportPills: [String] {
        [
            primaryTransport,
            streamingLabel,
            persistence
        ]
        .compactMap { $0 }
    }

    var accessibilityLabel: String {
        [
            "Runtime session descriptor",
            "primary transport \(primaryTransport)",
            transportKind.map { "transport kind \($0)" },
            "streaming \(streaming)",
            streamingLabel.map { "streaming mode \($0)" },
            persistence.map { "persistence \($0)" },
            fallbackTransport.map { "fallback \($0)" },
            sessionPath.map { "path \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    static func make(
        session: ClawJSRuntimeLensSnapshot.SessionDescriptor
    ) -> ClawJSRuntimeLensSessionDescriptorPresentation {
        let transportKind = session.transport?.kind
        let primaryTransport = session.primaryTransport ?? transportKind ?? "unknown"
        let streaming = session.transport?.streaming == true || session.streamingMode != nil
        let fallback = normalizedFallback(session.fallbackTransport)

        return ClawJSRuntimeLensSessionDescriptorPresentation(
            primaryTransport: primaryTransport,
            transportKind: transportKind,
            streaming: streaming,
            streamingLabel: streaming ? (session.streamingMode ?? "streaming") : nil,
            persistence: session.sessionPersistence,
            fallbackTransport: fallback,
            sessionPath: session.sessionPath,
            hasFallback: fallback != nil,
            hasPath: session.sessionPath != nil
        )
    }

    private static func normalizedFallback(_ fallback: String?) -> String? {
        guard let fallback, fallback != "none" else { return nil }
        return fallback
    }
}
