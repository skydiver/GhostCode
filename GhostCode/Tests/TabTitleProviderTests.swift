import XCTest
import Combine
@testable import Ghostty

final class TabTitleProviderTests: XCTestCase {
    func testFollowsLiveTitleWithFallbackForEmpty() {
        let titles = PassthroughSubject<String, Never>()
        let provider = TabTitleProvider(initialTitle: "vim", fallback: "shell", titles: titles.eraseToAnyPublisher())
        XCTAssertEqual(provider.displayTitle, "vim")

        let updated = expectation(description: "title updated")
        let cancellable = provider.$displayTitle.dropFirst().sink { _ in updated.fulfill() }
        titles.send("")
        wait(for: [updated], timeout: 1)

        XCTAssertEqual(provider.displayTitle, "shell")
        cancellable.cancel()
    }

    func testIsReleasedWhileTitlePublisherIsAlive() {
        let titles = PassthroughSubject<String, Never>()
        weak var weakProvider: TabTitleProvider?
        autoreleasepool {
            let provider = TabTitleProvider(initialTitle: "vim", fallback: "shell", titles: titles.eraseToAnyPublisher())
            weakProvider = provider
        }
        XCTAssertNil(weakProvider, "TabTitleProvider is retained by its own subscription")
    }
}
