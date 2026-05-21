import Combine
import XCTest
@testable import Clawix

@MainActor
final class VisualClockTests: XCTestCase {
    private final class FakeTimer: VisualClock.ClockTimer {
        let interval: TimeInterval
        let tick: @MainActor () -> Void
        private(set) var invalidated = false

        init(interval: TimeInterval, tick: @escaping @MainActor () -> Void) {
            self.interval = interval
            self.tick = tick
        }

        @MainActor
        func fire() {
            tick()
        }

        func invalidate() {
            invalidated = true
        }
    }

    private final class FakeTimerRecorder {
        var timers: [FakeTimer] = []

        func makeTimer(interval: TimeInterval, tick: @escaping @MainActor () -> Void) -> VisualClock.ClockTimer {
            let timer = FakeTimer(interval: interval, tick: tick)
            timers.append(timer)
            return timer
        }
    }

    func testFirstSecondsLeaseStartsOneSharedTimerAndLastReleaseStopsIt() {
        let recorder = FakeTimerRecorder()
        let clock = VisualClock(timerFactory: recorder.makeTimer(interval:tick:))

        let first = clock.acquire(.seconds)
        XCTAssertEqual(clock.activeLeaseCount(for: .seconds), 1)
        XCTAssertTrue(clock.isRunning(.seconds))
        XCTAssertEqual(recorder.timers.count, 1)
        XCTAssertEqual(recorder.timers[0].interval, VisualClock.secondsInterval, accuracy: 0.0001)

        let second = clock.acquire(.seconds)
        XCTAssertEqual(clock.activeLeaseCount(for: .seconds), 2)
        XCTAssertEqual(recorder.timers.count, 1)

        first.cancel()
        XCTAssertEqual(clock.activeLeaseCount(for: .seconds), 1)
        XCTAssertTrue(clock.isRunning(.seconds))
        XCTAssertFalse(recorder.timers[0].invalidated)

        second.cancel()
        XCTAssertEqual(clock.activeLeaseCount(for: .seconds), 0)
        XCTAssertFalse(clock.isRunning(.seconds))
        XCTAssertTrue(recorder.timers[0].invalidated)
    }

    func testSecondsAndShimmerChannelsAreIndependent() {
        let recorder = FakeTimerRecorder()
        let clock = VisualClock(timerFactory: recorder.makeTimer(interval:tick:))

        let seconds = clock.acquire(.seconds)
        let shimmer = clock.acquire(.shimmer)

        XCTAssertEqual(recorder.timers.count, 2)
        XCTAssertEqual(recorder.timers[0].interval, VisualClock.secondsInterval, accuracy: 0.0001)
        XCTAssertEqual(recorder.timers[1].interval, VisualClock.shimmerInterval, accuracy: 0.0001)
        XCTAssertTrue(clock.isRunning(.seconds))
        XCTAssertTrue(clock.isRunning(.shimmer))

        seconds.cancel()
        XCTAssertFalse(clock.isRunning(.seconds))
        XCTAssertTrue(clock.isRunning(.shimmer))
        XCTAssertTrue(recorder.timers[0].invalidated)
        XCTAssertFalse(recorder.timers[1].invalidated)

        shimmer.cancel()
        XCTAssertFalse(clock.isRunning(.shimmer))
        XCTAssertTrue(recorder.timers[1].invalidated)
    }

    func testFakeTimerTickPublishesToSubscribers() {
        let recorder = FakeTimerRecorder()
        let clock = VisualClock(timerFactory: recorder.makeTimer(interval:tick:))
        var received = 0
        var cancellables = Set<AnyCancellable>()
        clock.secondsPublisher
            .sink { _ in received += 1 }
            .store(in: &cancellables)

        let lease = clock.acquire(.seconds)
        XCTAssertEqual(received, 1)

        recorder.timers[0].fire()
        XCTAssertEqual(received, 2)

        lease.cancel()
    }
}
