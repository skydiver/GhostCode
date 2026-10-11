import XCTest
@testable import Ghostty

@MainActor
final class SerialTaskQueueTests: XCTestCase {
    func testRunsJobsOneAtATimeInOrder() async {
        let queue = SerialTaskQueue()
        var events: [String] = []
        let done = expectation(description: "both jobs ran")

        queue.enqueue {
            events.append("A start")
            try? await Task.sleep(nanoseconds: 50_000_000)
            events.append("A end")
        }
        queue.enqueue {
            events.append("B")
            done.fulfill()
        }

        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(events, ["A start", "A end", "B"])
    }
}
