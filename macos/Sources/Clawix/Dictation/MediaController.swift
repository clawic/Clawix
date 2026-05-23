import Foundation

/// Mutes system audio output while a dictation session is active so a
/// running video, music track, or notification beep doesn't bleed into
/// the microphone (especially with built-in mics or AirPods).
///
/// Mute state is read and written through the native Mac action broker.
///
/// We track whether *we* did the muting so we never unmute audio that
/// the user had already muted before starting dictation. After stop,
/// the unmute is delayed by `resumeDelaySeconds` to let any pending
/// app resume cleanly without a volume snap.
@MainActor
final class MediaController {

    static let shared = MediaController()

    /// `true` when the toggle is enabled. Default ON: this is the
    /// behaviour 95% of users want and matches the reference dictation
    /// tools we benchmarked against.
    nonisolated static let enabledKey = "dictation.muteAudioWhileRecording"

    /// Seconds to wait before unmuting after the session ends. 0 by
    /// default. Up to 5; values >5 land in Advanced settings UI.
    nonisolated static let resumeDelayKey = "dictation.muteResumeDelaySeconds"

    private let defaults: UserDefaults
    private let runner: NativeMacActionCommandRunning
    private let auditURL: URL?
    private var resumeWorkItem: DispatchWorkItem?
    /// Tracks a deferred mute scheduled via `muteAfter(_:)` so it can
    /// be cancelled if the session ends before it fires (would
    /// otherwise leave the system permanently muted).
    private var deferredMuteItem: DispatchWorkItem?
    /// Set to `true` only when *we* flipped the system mute on. The
    /// user might already have output muted before starting dictation;
    /// we leave that alone and restore nothing in that case.
    private var didMute: Bool = false
    private var muteReceiptId: String?

    init(
        defaults: UserDefaults = .standard,
        runner: NativeMacActionCommandRunning = NativeMacActionProcessRunner(),
        auditURL: URL? = nil
    ) {
        self.defaults = defaults
        self.runner = runner
        self.auditURL = auditURL
        // First-run defaults. Match the common dictation-tool default
        // so users migrating across tools see consistent behaviour.
        if defaults.object(forKey: Self.enabledKey) == nil {
            defaults.set(true, forKey: Self.enabledKey)
        }
        if defaults.object(forKey: Self.resumeDelayKey) == nil {
            defaults.set(0, forKey: Self.resumeDelayKey)
        }
    }

    /// Read the current toggle state. Read each call so flipping it in
    /// Settings takes effect on the next dictation without restart.
    var isEnabled: Bool {
        defaults.bool(forKey: Self.enabledKey)
    }

    var resumeDelaySeconds: Int {
        let v = defaults.integer(forKey: Self.resumeDelayKey)
        return max(0, min(5, v))
    }

    // MARK: - Public lifecycle

    /// Mute system output if the toggle is on and the user hadn't
    /// already muted it. Idempotent across repeated calls.
    func muteIfNeeded() {
        guard isEnabled else { return }
        // Drop any deferred mute scheduled for this session — we're
        // about to mute synchronously below.
        deferredMuteItem?.cancel()
        deferredMuteItem = nil
        // If a deferred unmute from a previous session is queued,
        // cancel it AND inherit ownership: the system is currently
        // muted because *we* muted it before, even if the AppleScript
        // unmute didn't fire yet. Without this, a fast cancel→start
        // sequence would orphan the mute (didMute=false), so the next
        // stop wouldn't restore audio.
        let inheritedPendingMute = (resumeWorkItem != nil)
        resumeWorkItem?.cancel()
        resumeWorkItem = nil
        if inheritedPendingMute {
            didMute = true
            return
        }
        // Don't re-mute: user already had output muted, keep their
        // state authoritative.
        if currentMutedState() == true {
            didMute = false
            return
        }
        if let receipt = setMuted(true) {
            didMute = true
            muteReceiptId = receipt.receiptId
        }
    }

    /// Synchronously unmute now, ignoring `resumeDelaySeconds`. Used
    /// just before playing a cue (cancel/stop/done) so the cue is
    /// audible. No-op if we didn't mute.
    func unmuteImmediately() {
        // Drop any pending deferred mute from this session so it
        // doesn't fire after the unmute and leave the system muted.
        deferredMuteItem?.cancel()
        deferredMuteItem = nil
        resumeWorkItem?.cancel()
        resumeWorkItem = nil
        guard didMute, muteReceiptId != nil else { return }
        didMute = false
        muteReceiptId = nil
        _ = setMuted(false)
    }

    /// Schedule `muteIfNeeded()` after `delay` seconds. Used at the
    /// start of a session so the start cue plays into an unmuted
    /// system; the mute kicks in once the cue has finished.
    func muteAfter(_ delay: TimeInterval) {
        guard isEnabled else { return }
        // Cancel any pending unmute from a prior session so we don't
        // re-enter a clean state mid-session.
        resumeWorkItem?.cancel()
        resumeWorkItem = nil
        // Replace any in-flight deferred mute so we don't double-fire.
        deferredMuteItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.deferredMuteItem = nil
            self?.muteIfNeeded()
        }
        deferredMuteItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Unmute after `resumeDelaySeconds`. No-op if we didn't mute.
    func unmuteAfterDelay() {
        // Drop any pending deferred mute scheduled by `muteAfter(_:)`
        // so it doesn't fire after we return to idle and silently
        // re-mute the system.
        deferredMuteItem?.cancel()
        deferredMuteItem = nil
        guard didMute else {
            // Make sure no stale work item is left behind (e.g. user
            // toggled the setting off mid-session).
            resumeWorkItem?.cancel()
            resumeWorkItem = nil
            return
        }
        didMute = false
        let delay = TimeInterval(resumeDelaySeconds)
        let work = DispatchWorkItem { [weak self] in
            _ = self?.setMuted(false)
            self?.muteReceiptId = nil
        }
        resumeWorkItem?.cancel()
        resumeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Broker bridge

    /// Returns `true` if currently muted, `false` if not, `nil` if the
    /// brokered query failed.
    private func currentMutedState() -> Bool? {
        let receipt = NativeMacActionBroker.evaluate(
            brokerRequest(capabilityId: "mac.audio.mute.status"),
            auditURL: auditURL,
            runner: runner
        )
        guard receipt.outcome == .executed, let raw = receipt.outputs.first?.lowercased() else {
            logBrokerFailure("mute status", receipt)
            return nil
        }
        if raw.contains("muted") && !raw.contains("unmuted") { return true }
        if raw.contains("unmuted") || raw.contains("false") { return false }
        return nil
    }

    /// Returns `true` if the system mute write succeeded.
    @discardableResult
    private func setMuted(_ muted: Bool) -> NativeMacActionReceipt? {
        let receipt = NativeMacActionBroker.evaluate(
            brokerRequest(capabilityId: "mac.audio.mute.set", arguments: ["muted": String(muted)]),
            auditURL: auditURL,
            runner: runner
        )
        guard receipt.outcome == .executed else {
            logBrokerFailure("mute set", receipt)
            return nil
        }
        return receipt
    }

    private func brokerRequest(
        capabilityId: String,
        arguments: [String: String] = [:]
    ) -> NativeMacActionRequest {
        NativeMacActionRequest(
            capabilityId: capabilityId,
            actorId: "clawix.dictation",
            origin: .userUI,
            actorKind: "user_ui",
            arguments: arguments
        )
    }

    private func logBrokerFailure(_ action: String, _ receipt: NativeMacActionReceipt) {
        NSLog("[Clawix.MediaController] broker \(action) failed with outcome=\(receipt.outcome.rawValue)")
    }
}
