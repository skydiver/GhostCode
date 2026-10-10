import XCTest
import Combine
@testable import Ghostty

final class PulseClockTests: XCTestCase {

    func test_phaseTogglesAtConfiguredInterval() {
        let clock = PulseClock(interval: 0.05)  // 50ms for fast test
        clock.setActive(true)
        let initial = clock.phase

        var seen: [Bool] = []
        let bothToggles = expectation(description: "two phase toggles")
        var cancellable: AnyCancellable?
        cancellable = clock.$phase
            .dropFirst()
            .sink { value in
                seen.append(value)
                if seen.count == 2 {
                    bothToggles.fulfill()
                    cancellable?.cancel()
                }
            }

        wait(for: [bothToggles], timeout: 1.0)
        XCTAssertEqual(seen, [!initial, initial], "phase must alternate, not latch")
    }

    func test_clockIsStoppedOnDeinit() {
        weak var weakClock: PulseClock?
        autoreleasepool {
            let clock = PulseClock(interval: 0.05)
            weakClock = clock
            _ = clock.phase  // touch
        }
        // Outside autoreleasepool the clock must be released.
        XCTAssertNil(weakClock, "PulseClock leaked — timer is retaining self")
    }

    func test_inactiveClockDoesNotTick() {
        let clock = PulseClock(interval: 0.02)
        var ticks = 0
        let cancellable = clock.$phase.dropFirst().sink { _ in ticks += 1 }

        RunLoop.main.run(until: Date().addingTimeInterval(0.15))

        XCTAssertEqual(ticks, 0)
        cancellable.cancel()
    }

    func test_deactivatingStopsTicksAndResetsPhase() {
        let clock = PulseClock(interval: 0.02)
        clock.setActive(true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        clock.setActive(false)
        var ticks = 0
        let cancellable = clock.$phase.dropFirst().sink { _ in ticks += 1 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))

        XCTAssertFalse(clock.phase)
        XCTAssertEqual(ticks, 0)
        cancellable.cancel()
    }
}
