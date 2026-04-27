import XCTest
import Combine
@testable import Ghostty

final class PulseClockTests: XCTestCase {

    func test_phaseTogglesAtConfiguredInterval() {
        let clock = PulseClock(interval: 0.05)  // 50ms for fast test
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
}
