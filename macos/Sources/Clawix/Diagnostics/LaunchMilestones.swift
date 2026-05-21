import Foundation

/// One-shot launch milestones used by the release startup contract.
///
/// Keep these names stable: the private cold/warm harness and the public
/// startup release checker both treat them as the measurement wire format.
enum LaunchMilestone: String, CaseIterable {
    case processStart = "process_start"
    case appInitStart = "app_init_start"
    case appInitEnd = "app_init_end"
    case firstWindow = "first_window"
    case firstSidebarPaint = "first_sidebar_paint"
    case firstChatInteractive = "first_chat_interactive"
    case coreReady = "core_ready"
}

enum LaunchMilestones {
    private static let lock = NSLock()
    private static var emitted = Set<LaunchMilestone>()

    static var names: [String] {
        LaunchMilestone.allCases.map(\.rawValue)
    }

    static func mark(_ milestone: LaunchMilestone) {
        lock.lock()
        let shouldEmit = emitted.insert(milestone).inserted
        let emitter = testEmitter
        lock.unlock()
        guard shouldEmit else { return }
        if let emitter {
            emitter(milestone)
        } else {
            emitSignpost(milestone)
        }
    }

    private static func emitSignpost(_ milestone: LaunchMilestone) {
        switch milestone {
        case .processStart:
            PerfSignpost.launch.event("process_start")
        case .appInitStart:
            PerfSignpost.launch.event("app_init_start")
        case .appInitEnd:
            PerfSignpost.launch.event("app_init_end")
        case .firstWindow:
            PerfSignpost.launch.event("first_window")
        case .firstSidebarPaint:
            PerfSignpost.launch.event("first_sidebar_paint")
        case .firstChatInteractive:
            PerfSignpost.launch.event("first_chat_interactive")
        case .coreReady:
            PerfSignpost.launch.event("core_ready")
        }
    }

    // Test hooks stay internal so @testable imports can verify one-shot
    // behavior without depending on the unified log.
    static var testEmitter: ((LaunchMilestone) -> Void)?

    static func resetForTests() {
        lock.lock()
        emitted.removeAll()
        testEmitter = nil
        lock.unlock()
    }
}
