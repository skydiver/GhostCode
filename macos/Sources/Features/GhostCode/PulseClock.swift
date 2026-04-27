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
    init(interval: TimeInterval = 0.7) {
        self.timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.phase.toggle()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }
}
