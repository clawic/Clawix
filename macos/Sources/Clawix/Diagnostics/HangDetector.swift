import Foundation
import CoreFoundation
import os
import ClawixCore

/// Diagnostics-gated main-thread hang detector.
///
/// Listens to runloop activity transitions on `.commonModes` and
/// records when the main thread enters a "processing" phase. A guard
/// thread polling at 100 ms decides the main thread has been stuck if
/// `now - enteredAt > thresholdMs` (default 250 ms, override via
/// `CLAWIX_HANG_MS=<int>`). On detection it emits a signpost in the
/// `hang` category, a `Logger.warning`, and schedules a post-resume
/// `Thread.callStackSymbols` capture so the trace shows what the main
/// thread was doing right after the stall released.
///
/// Why not rely on `RenderProbe.HitchProbe`? `HitchProbe` samples
/// post-frame at 60 Hz on the main runloop's timer mode, so it cannot
/// see stalls during scroll / window drag (event-tracking mode), or
/// any synchronous block that holds the runloop past frame
/// boundaries. `HangDetector` watches every runloop cycle on every
/// common mode, including event tracking.
///
/// Intentionally activated only by explicit diagnostics surfaces or
/// `CLAWIX_FORCE_DIAGNOSTICS_SAMPLERS=1`. Override release gating with
/// `CLAWIX_FORCE_HANG_DETECTOR=1` when a standalone repro needs it.
enum HangDetector {
    nonisolated(unsafe) private static var observer: CFRunLoopObserver?
    nonisolated(unsafe) private static var enteredAt: CFAbsoluteTime = 0
    nonisolated(unsafe) private static var lastReportedAt: CFAbsoluteTime = 0
    nonisolated(unsafe) private static var guardTimer: DispatchSourceTimer?
    private static let guardQueue = DispatchQueue(label: "clawix.diag.hang", qos: .utility)

    static let thresholdMs: Double = {
        if let raw = ClawixEnv.value(ClawixEnv.hangMs),
           let value = Double(raw), value > 0 {
            return value
        }
        return 250
    }()

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.example.clawix",
        category: ClawixDiagnosticLogCategory.hang
    )

    static func shouldStartFromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        ClawixEnv.isEnabled(ClawixEnv.forceDiagnosticsSamplers, in: environment)
            || ClawixEnv.isEnabled(ClawixEnv.forceHangDetector, in: environment)
    }

    static func startIfRequestedByEnvironment() {
        guard shouldStartFromEnvironment() else { return }
        start(force: true)
    }

    static func startFromDiagnosticsSurface() {
        start(force: true)
    }

    static func start() {
        startIfRequestedByEnvironment()
    }

    private static func start(force: Bool) {
        // Apple's recommendation is "investigate hangs in development";
        // normal launch should not pay the runloop observer cost.
        guard force || shouldStartFromEnvironment() else { return }
        #if !DEBUG
        guard force || ClawixEnv.isEnabled(ClawixEnv.forceHangDetector) else { return }
        #endif

        guard observer == nil else { return }

        let activities: CFRunLoopActivity = [
            .entry, .beforeTimers, .beforeSources, .afterWaiting, .beforeWaiting, .exit
        ]

        // `order: 999_999` runs the observer AFTER everyone else in the
        // same activity slot, so the timestamp brackets the actual
        // user-code work the runloop is about to do (or just did).
        let cfActivities = CFRunLoopActivity(rawValue: activities.rawValue)
        observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            cfActivities.rawValue,
            true,
            999_999
        ) { _, activity in
            switch activity {
            case .beforeTimers, .beforeSources, .afterWaiting:
                enteredAt = CFAbsoluteTimeGetCurrent()
            case .beforeWaiting, .exit:
                enteredAt = 0
            default:
                break
            }
        }
        if let observer {
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }

        let timer = DispatchSource.makeTimerSource(queue: guardQueue)
        timer.schedule(
            deadline: .now() + 0.1,
            repeating: 0.1,
            leeway: .milliseconds(50)
        )
        timer.setEventHandler {
            let entered = enteredAt
            guard entered > 0 else { return }
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - entered) * 1000.0
            // Only re-report if the main thread resumed and stalled
            // again on a different cycle. Otherwise a 5 s freeze would
            // log fifty identical warnings as the guard polls.
            guard elapsedMs > thresholdMs, entered != lastReportedAt else { return }
            lastReportedAt = entered
            report(elapsedMs: elapsedMs)
        }
        timer.resume()
        guardTimer = timer
    }

    private static func report(elapsedMs: Double) {
        let ms = Int(elapsedMs)
        let threshold = Int(thresholdMs)
        PerfSignpost.hang.event("main-stalled", ms)
        log.warning(
            "main thread stalled \(ms, privacy: .public) ms (threshold \(threshold, privacy: .public) ms)"
        )
        // Capture the post-resume main-thread stack. By the time this
        // closure runs the stall has unblocked, so the symbols
        // describe what the main thread is doing right after release.
        // Imperfect (the actual culprit may already have returned) but
        // useful as a first pass without entitlements; pair with an
        // Instruments Time Profiler trace for the live picture.
        DispatchQueue.main.async {
            let symbols = Thread.callStackSymbols.prefix(20).joined(separator: "\n")
            log.warning("post-stall main stack:\n\(symbols, privacy: .public)")
        }
    }
}
