import Combine
import Foundation

@MainActor
final class VisualClock {
    static let shared = VisualClock()
    static let secondsInterval: TimeInterval = 1.0
    static let shimmerInterval: TimeInterval = 1.0 / 15.0

    enum Channel {
        case seconds
        case shimmer
    }

    protocol ClockTimer: AnyObject {
        func invalidate()
    }

    typealias TimerFactory = @MainActor (_ interval: TimeInterval, _ tick: @escaping @MainActor () -> Void) -> ClockTimer

    private struct ChannelState {
        var leaseCount = 0
        var timer: ClockTimer?
    }

    private final class FoundationClockTimer: ClockTimer {
        private let timer: Timer

        init(_ timer: Timer) {
            self.timer = timer
        }

        func invalidate() {
            timer.invalidate()
        }
    }

    @MainActor
    final class Lease {
        private weak var clock: VisualClock?
        private let channel: Channel
        private var active = true

        fileprivate init(clock: VisualClock, channel: Channel) {
            self.clock = clock
            self.channel = channel
        }

        deinit {
            if active {
                let clock = clock
                let channel = channel
                Task { @MainActor in
                    clock?.release(channel)
                }
            }
        }

        func cancel() {
            guard active else { return }
            active = false
            clock?.release(channel)
        }
    }

    private let timerFactory: TimerFactory
    private var secondsState = ChannelState()
    private var shimmerState = ChannelState()
    private let secondsSubject = PassthroughSubject<Date, Never>()
    private let shimmerSubject = PassthroughSubject<Date, Never>()

    var secondsPublisher: AnyPublisher<Date, Never> {
        secondsSubject.eraseToAnyPublisher()
    }

    var shimmerPublisher: AnyPublisher<Date, Never> {
        shimmerSubject.eraseToAnyPublisher()
    }

    init(timerFactory: @escaping TimerFactory = VisualClock.makeTimer(interval:tick:)) {
        self.timerFactory = timerFactory
    }

    func acquire(_ channel: Channel) -> Lease {
        retain(channel)
        return Lease(clock: self, channel: channel)
    }

    func activeLeaseCount(for channel: Channel) -> Int {
        state(for: channel).leaseCount
    }

    func isRunning(_ channel: Channel) -> Bool {
        state(for: channel).timer != nil
    }

    private func retain(_ channel: Channel) {
        var state = state(for: channel)
        state.leaseCount += 1
        if state.leaseCount == 1 {
            publish(Date(), on: channel)
            state.timer = timerFactory(interval(for: channel)) { [weak self] in
                self?.publish(Date(), on: channel)
            }
        }
        setState(state, for: channel)
    }

    private func release(_ channel: Channel) {
        var state = state(for: channel)
        guard state.leaseCount > 0 else { return }
        state.leaseCount -= 1
        if state.leaseCount == 0 {
            state.timer?.invalidate()
            state.timer = nil
        }
        setState(state, for: channel)
    }

    private func interval(for channel: Channel) -> TimeInterval {
        switch channel {
        case .seconds:
            return Self.secondsInterval
        case .shimmer:
            return Self.shimmerInterval
        }
    }

    private func publish(_ date: Date, on channel: Channel) {
        switch channel {
        case .seconds:
            secondsSubject.send(date)
        case .shimmer:
            shimmerSubject.send(date)
        }
    }

    private func state(for channel: Channel) -> ChannelState {
        switch channel {
        case .seconds:
            return secondsState
        case .shimmer:
            return shimmerState
        }
    }

    private func setState(_ state: ChannelState, for channel: Channel) {
        switch channel {
        case .seconds:
            secondsState = state
        case .shimmer:
            shimmerState = state
        }
    }

    private static func makeTimer(interval: TimeInterval, tick: @escaping @MainActor () -> Void) -> ClockTimer {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                tick()
            }
        }
        timer.tolerance = interval * 0.2
        return FoundationClockTimer(timer)
    }
}
