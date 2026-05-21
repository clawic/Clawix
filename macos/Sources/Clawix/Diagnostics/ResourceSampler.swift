import Foundation
import Darwin
import ClawixCore
import os

/// Samples process resident memory, physical footprint and CPU usage
/// when an explicit diagnostics surface asks for it. Periodic sampling
/// is intentionally opt-in so normal launch does not add a background
/// loop before first paint. Each tick is emitted as a signpost event
/// in the `resource` category so traces correlate spikes against
/// whatever else is running at the same wall-clock.
///
/// Use `startIfNeeded(reason:)` for diagnostics sessions that need a
/// periodic lane and `sampleNowAndPersist()` for one-shot rescue exports.
enum ResourceSampler {
    static let lastResourcesFileName = "last-resources.json"
    static let resourceSamplesFileName = "resource-samples.json"

    private static let queue = DispatchQueue(label: "clawix.diag.sampler", qos: .utility)
    nonisolated(unsafe) private static var timer: DispatchSourceTimer?
    nonisolated(unsafe) private static var lastTotalTicks: UInt64 = 0
    nonisolated(unsafe) private static var lastIdleTicks: UInt64 = 0
    nonisolated(unsafe) private static var lastSample: Sample?
    nonisolated(unsafe) private static var samples: [Sample] = []
    private static let sampleLimit = 7_200

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.example.clawix",
        category: "resource-sampler"
    )

    struct Sample: Codable {
        let timestamp: TimeInterval
        let residentBytes: UInt64
        let footprintBytes: UInt64
        /// Process CPU usage, normalised so 100 = one fully busy core.
        /// On a hex-core machine the realistic max is therefore ~600.
        let processCpuPercent: Double
        let appVersion: String?
        let buildNumber: String?
    }

    static func shouldStartPeriodicSampler(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        ClawixEnv.isEnabled(ClawixEnv.forceDiagnosticsSamplers, in: environment)
    }

    static func startIfNeeded(reason: String) {
        queue.async {
            guard timer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 1.0, repeating: 1.0, leeway: .milliseconds(200))
            t.setEventHandler { tick() }
            t.resume()
            timer = t
            log.info("ResourceSampler started for \(reason, privacy: .public)")
        }
    }

    static func start() {
        startIfNeeded(reason: "legacy")
    }

    static func stop() {
        queue.async {
            timer?.cancel()
            timer = nil
        }
    }

    /// Captures one sample immediately and persists it to disk. Use
    /// for explicit rescue/diagnostics actions when the periodic
    /// sampler has not been started.
    static func sampleNowAndPersist() {
        queue.sync {
            tick()
            persistLastSampleOnQueue()
        }
    }

    /// Persists the most recent sample to disk without starting the
    /// sampler. Normal app launch may never have a sample, and that is
    /// expected unless a diagnostics surface opted in.
    static func persistLastSample() {
        queue.sync {
            persistLastSampleOnQueue()
        }
    }

    static func latestHealthSnapshot(
        bridgeReachable: Bool? = nil,
        runtimeCount: Int? = nil
    ) -> RescueRuntimeHealthSnapshot? {
        queue.sync {
            guard let sample = lastSample else {
                guard bridgeReachable != nil || runtimeCount != nil else { return nil }
                return RescueRuntimeHealthSnapshot(
                    bridgeReachable: bridgeReachable,
                    runtimeCount: runtimeCount
                )
            }
            return RescueRuntimeHealthSnapshot(
                processCpuPercent: sample.processCpuPercent,
                residentBytes: sample.residentBytes,
                footprintBytes: sample.footprintBytes,
                bridgeReachable: bridgeReachable,
                runtimeCount: runtimeCount
            )
        }
    }

    static func persistedHealthSnapshot(
        from url: URL?,
        bridgeReachable: Bool? = nil,
        runtimeCount: Int? = nil
    ) -> RescueRuntimeHealthSnapshot? {
        guard let url,
              let data = try? Data(contentsOf: url),
              let sample = try? JSONDecoder().decode(Sample.self, from: data) else {
            return nil
        }
        return RescueRuntimeHealthSnapshot(
            processCpuPercent: sample.processCpuPercent,
            residentBytes: sample.residentBytes,
            footprintBytes: sample.footprintBytes,
            bridgeReachable: bridgeReachable,
            runtimeCount: runtimeCount
        )
    }

    /// Resolves `~/Library/Application Support/<bundleId>/Diagnostics/<name>`,
    /// creating the directory tree if needed. Returns nil on sandbox
    /// or filesystem errors (the caller should treat that as "no
    /// diagnostics dump this run", not a fatal condition).
    static func diagnosticsFileURL(named name: String) -> URL? {
        let fm = FileManager.default
        let bundleId = Bundle.main.bundleIdentifier ?? "clawix.desktop"
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = support
            .appendingPathComponent(bundleId, isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return dir.appendingPathComponent(name)
    }

    private static func tick() {
        let sample = captureSample()
        lastSample = sample
        samples.append(sample)
        if samples.count > sampleLimit {
            samples.removeFirst(samples.count - sampleLimit)
        }
        // Each metric is its own event so Instruments charts the values
        // straight from the trace, no log parsing required.
        PerfSignpost.resource.event("rss_mb", Int(sample.residentBytes / 1024 / 1024))
        PerfSignpost.resource.event("footprint_mb", Int(sample.footprintBytes / 1024 / 1024))
        PerfSignpost.resource.event("cpu_pct", sample.processCpuPercent)
    }

    private static func captureSample() -> Sample {
        let info = Bundle.main.infoDictionary
        return Sample(
            timestamp: Date().timeIntervalSince1970,
            residentBytes: residentSize(),
            footprintBytes: footprint(),
            processCpuPercent: processCpuPercent(),
            appVersion: info?["CFBundleShortVersionString"] as? String,
            buildNumber: info?["CFBundleVersion"] as? String
        )
    }

    private static func persistLastSampleOnQueue() {
        guard let sample = lastSample else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let url = diagnosticsFileURL(named: lastResourcesFileName),
           let data = try? encoder.encode(sample) {
            try? data.write(to: url, options: .atomic)
        }
        if let url = diagnosticsFileURL(named: resourceSamplesFileName),
           let data = try? encoder.encode(samples) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Mach calls

    private static func residentSize() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size
        )
        let kerr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    intPtr,
                    &count
                )
            }
        }
        return kerr == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }

    private static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let kerr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    intPtr,
                    &count
                )
            }
        }
        return kerr == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }

    /// Aggregates per-thread CPU usage (`thread_basic_info.cpu_usage`)
    /// across all live threads of the current process. Mirrors what
    /// Activity Monitor's "%CPU" column reports: one fully busy core
    /// reads as 100, an 8-thread saturated process can hit ~800. The
    /// `TH_USAGE_SCALE` constant is the kernel's fixed-point scale.
    private static func processCpuPercent() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let kerr = task_threads(mach_task_self_, &threadList, &threadCount)
        guard kerr == KERN_SUCCESS, let threads = threadList else { return 0 }
        defer {
            // `threads` is the base of the thread-id array allocated
            // by the kernel for us; vm_deallocate releases that page.
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: threads)),
                vm_size_t(MemoryLayout<thread_t>.size * Int(threadCount))
            )
        }
        var total: Double = 0
        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(
                MemoryLayout<thread_basic_info>.size / MemoryLayout<natural_t>.size
            )
            let res = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
                ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                    thread_info(
                        threads[i],
                        thread_flavor_t(THREAD_BASIC_INFO),
                        intPtr,
                        &count
                    )
                }
            }
            if res == KERN_SUCCESS, (info.flags & TH_FLAGS_IDLE) == 0 {
                total += (Double(info.cpu_usage) / Double(TH_USAGE_SCALE)) * 100.0
            }
        }
        return total
    }
}
