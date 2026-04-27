import XCTest
import Combine
@testable import Ghostty

final class PulseClockTests: XCTestCase {

    func test_phaseTogglesAtConfiguredInterval() {
        let clock = PulseClock(interval: 0.05)  // 50ms for fast test
        let initial = clock.phase

        let toggled = expectation(description: "phase toggles")
        var cancellable: AnyCancellable?
        cancellable = clock.$phase
            .dropFirst()
            .sink { value in
                XCTAssertEqual(value, !initial)
                toggled.fulfill()
                cancellable?.cancel()
            }

        wait(for: [toggled], timeout: 1.0)
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
