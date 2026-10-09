import XCTest
@testable import Ghostty

final class ExecutableLauncherTests: XCTestCase {

    func testLaunchWithNonexistentPathCallsFailureHandler() {
        let expectation = self.expectation(description: "failure handler invoked")
        var receivedPath: String?
        var receivedReason: String?

        ExecutableLauncher.launch(
            executablePath: "/nonexistent/path/to/binary",
            projectPath: "/tmp"
        ) { path, reason in
            receivedPath = path
            receivedReason = reason
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedPath, "/nonexistent/path/to/binary")
        XCTAssertNotNil(receivedReason)
        XCTAssertFalse(receivedReason?.isEmpty ?? true)
    }

    func testLaunchWithNonExecutableFileCallsFailureHandler() throws {
        // Create a regular (non-executable) file and verify the launcher rejects it.
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-executable-\(UUID().uuidString)")
        try "hello".data(using: .utf8)!.write(to: tempFile)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempFile)
        }

        let expectation = self.expectation(description: "failure handler invoked")
        var receivedPath: String?

        ExecutableLauncher.launch(
            executablePath: tempFile.path,
            projectPath: "/tmp"
        ) { path, _ in
            receivedPath = path
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedPath, tempFile.path)
    }
}
