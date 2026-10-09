import Foundation
import Combine

/// Shared timer-driven boolean. Multiple SwiftUI views observe `phase` to
/// produce synchronized opacity animations — the visual rhythm reads as a
/// single coordinated alert rather than independent flickers.
final class PulseClock: ObservableObject {
    @Published private(set) var phase: Bool = false

    private var timer: Timer?

    /// - Parameter interval: half-period in seconds. Default matches
    ///   the design spec (0.7s per ease-in-out leg → 1.4s full cycle).
    ///
    /// The timer is explicitly added to the main run loop so its lifecycle
    /// is independent of the caller's run loop. `Timer.invalidate()` must
    /// be called on the same run loop the timer was scheduled on; pinning
    /// to `.main` makes that contract correct regardless of where init runs.
    init(interval: TimeInterval = 0.7) {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.phase.toggle()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
    }
}
