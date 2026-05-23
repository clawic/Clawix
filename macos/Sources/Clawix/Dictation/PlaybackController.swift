import Foundation

/// Pauses the currently playing media app while a dictation session is
/// active and resumes only that app afterwards. Complementary to
/// `MediaController` (which mutes system output): pausing keeps the
/// track in place rather than letting it advance silently.
///
/// Player IPC is owned by the native Mac action broker. Clawix keeps only
/// session coordination and never directly targets media apps.
///
/// Only one app is paused per session (the first one we find playing
/// in the broker target priority order Music → Podcasts → TV) so resume can't
/// accidentally start an app that wasn't playing in the first place.
@MainActor
final class PlaybackController {

    static let shared = PlaybackController()

    nonisolated static let enabledKey = "dictation.pauseMediaWhileRecording"
    nonisolated static let resumeDelayKey = "dictation.pauseResumeDelaySeconds"

    private let defaults: UserDefaults
    private let runner: NativeMacActionCommandRunning
    private let auditURL: URL?
    private var resumeWorkItem: DispatchWorkItem?
    /// Identifier of the app we paused (`Music`, `Spotify`,
    /// `Podcasts`). Nil when no pause happened.
    private var pausedApp: String?
    private var pauseReceiptId: String?

    private static let candidateApps: [String] = ["Music", "Podcasts", "TV"]

    init(
        defaults: UserDefaults = .standard,
        runner: NativeMacActionCommandRunning = NativeMacActionProcessRunner(),
        auditURL: URL? = nil
    ) {
        self.defaults = defaults
        self.runner = runner
        self.auditURL = auditURL
        // Default OFF: this is more intrusive than muting. The mute
        // toggle covers the noise problem; pause is for users who'd
        // rather not lose their place in the track.
        if defaults.object(forKey: Self.enabledKey) == nil {
            defaults.set(false, forKey: Self.enabledKey)
        }
        if defaults.object(forKey: Self.resumeDelayKey) == nil {
            defaults.set(0, forKey: Self.resumeDelayKey)
        }
    }

    var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }
    var resumeDelaySeconds: Int {
        let v = defaults.integer(forKey: Self.resumeDelayKey)
        return max(0, min(5, v))
    }

    // MARK: - Lifecycle

    func pauseIfNeeded() {
        guard isEnabled else { return }
        resumeWorkItem?.cancel()
        resumeWorkItem = nil

        for app in Self.candidateApps {
            guard playbackState(app: app) == "playing" else { continue }
            if let receipt = pause(app: app) {
                pausedApp = app
                pauseReceiptId = receipt.receiptId
                break
            }
        }
    }

    func resumeAfterDelay() {
        guard let app = pausedApp, pauseReceiptId != nil else {
            resumeWorkItem?.cancel()
            resumeWorkItem = nil
            return
        }
        pausedApp = nil
        pauseReceiptId = nil
        let delay = TimeInterval(resumeDelaySeconds)
        let work = DispatchWorkItem { [weak self] in
            _ = self?.resume(app: app)
        }
        resumeWorkItem?.cancel()
        resumeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Broker helpers

    private func playbackState(app: String) -> String? {
        let receipt = NativeMacActionBroker.evaluate(
            brokerRequest(capabilityId: "mac.media.playback.status", app: app),
            auditURL: auditURL,
            runner: runner
        )
        guard receipt.outcome == .executed else {
            logBrokerFailure("playback status", receipt)
            return nil
        }
        return receipt.outputs.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    @discardableResult
    private func pause(app: String) -> NativeMacActionReceipt? {
        let receipt = NativeMacActionBroker.evaluate(
            brokerRequest(capabilityId: "mac.media.playback.pause", app: app),
            auditURL: auditURL,
            runner: runner
        )
        guard receipt.outcome == .executed else {
            logBrokerFailure("playback pause", receipt)
            return nil
        }
        return receipt
    }

    @discardableResult
    private func resume(app: String) -> NativeMacActionReceipt? {
        let receipt = NativeMacActionBroker.evaluate(
            brokerRequest(capabilityId: "mac.media.playback.resume", app: app),
            auditURL: auditURL,
            runner: runner
        )
        guard receipt.outcome == .executed else {
            logBrokerFailure("playback resume", receipt)
            return nil
        }
        return receipt
    }

    private func brokerRequest(capabilityId: String, app: String) -> NativeMacActionRequest {
        NativeMacActionRequest(
            capabilityId: capabilityId,
            actorId: "clawix.dictation",
            origin: .userUI,
            actorKind: "user_ui",
            arguments: ["app": app]
        )
    }

    private func logBrokerFailure(_ action: String, _ receipt: NativeMacActionReceipt) {
        NSLog("[Clawix.PlaybackController] broker \(action) failed with outcome=\(receipt.outcome.rawValue)")
    }
}
