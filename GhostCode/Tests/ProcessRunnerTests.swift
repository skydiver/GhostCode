import XCTest
@testable import Ghostty

final class ProcessRunnerTests: XCTestCase {
    func testReturnsStandardOutput() async {
        let data = await ProcessRunner.output(of: process("/bin/echo", ["hello"]), timeout: 5)
        XCTAssertEqual(data.flatMap { String(data: $0, encoding: .utf8) }, "hello\n")
    }

    func testReadsOutputLargerThanPipeBuffer() async {
        let data = await ProcessRunner.output(
            of: process("/bin/sh", ["-c", "yes x | head -c 200000"]),
            timeout: 5
        )
        XCTAssertEqual(data?.count, 200_000)
    }

    func testTerminatesProcessThatExceedsTimeout() async {
        let sleeper = process("/bin/sleep", ["30"])
        let start = Date()

        let data = await ProcessRunner.output(of: sleeper, timeout: 0.5)

        XCTAssertNil(data)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        sleeper.waitUntilExit()
        XCTAssertEqual(sleeper.terminationReason, .uncaughtSignal)
    }

    func testReturnsOutputWhenBackgroundChildKeepsPipeOpen() async {
        // A login profile can start a daemon that inherits stdout; the shell
        // has still finished, so its output must not be discarded.
        let start = Date()

        let data = await ProcessRunner.output(
            of: process("/bin/sh", ["-c", "echo done; /bin/sleep 30 &"]),
            timeout: 1
        )

        XCTAssertEqual(data.flatMap { String(data: $0, encoding: .utf8) }, "done\n")
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testReturnsNilWhenProcessCannotStart() async {
        let data = await ProcessRunner.output(of: process("/nonexistent/tool", []), timeout: 5)
        XCTAssertNil(data)
    }

    private func process(_ path: String, _ arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        return process
    }
}
