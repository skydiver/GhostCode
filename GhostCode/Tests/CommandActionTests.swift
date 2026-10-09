import XCTest
@testable import Ghostty

final class CommandActionTests: XCTestCase {

    func testActionReturnsSendTextWhenTextSet() {
        let item = CommandItem(
            label: "Refactor",
            text: "please refactor this",
            tooltip: nil,
            autoSend: true
        )
        if case .sendText(let text, let autoSend) = item.action {
            XCTAssertEqual(text, "please refactor this")
            XCTAssertTrue(autoSend)
        } else {
            XCTFail("Expected .sendText action, got \(String(describing: item.action))")
        }
    }

    func testActionRespectsAutoSendDefault() {
        let item = CommandItem(
            label: "Default",
            text: "x",
            tooltip: nil,
            autoSend: nil
        )
        if case .sendText(_, let autoSend) = item.action {
            XCTAssertFalse(autoSend, "autoSend should default to false")
        } else {
            XCTFail("Expected .sendText action")
        }
    }

    func testActionIsNilWhenTextIsNil() {
        let item = CommandItem(label: "Empty", text: nil, tooltip: nil, autoSend: nil)
        XCTAssertNil(item.action)
    }

    func testActionReturnsLaunchProcessWhenExecutableSet() {
        let item = CommandItem(
            label: "VSCode",
            text: nil,
            executable: "/usr/local/bin/code",
            tooltip: nil,
            autoSend: nil
        )
        if case .launchProcess(let path, let arguments) = item.action {
            XCTAssertEqual(path, "/usr/local/bin/code")
            XCTAssertNil(arguments, "arguments should be nil when not specified")
        } else {
            XCTFail("Expected .launchProcess action, got \(String(describing: item.action))")
        }
    }

    func testActionPrefersExecutableWhenBothSomehowSet() {
        // Defensive: decoder validation rejects items with both, but the action
        // computed property still picks executable first as a runtime safety net.
        let item = CommandItem(
            label: "Both",
            text: "hi",
            executable: "/bin/echo",
            tooltip: nil,
            autoSend: nil
        )
        if case .launchProcess(let path, _) = item.action {
            XCTAssertEqual(path, "/bin/echo")
        } else {
            XCTFail("Expected executable to win over text")
        }
    }

    func testActionForwardsArgumentsWhenSet() {
        let item = CommandItem(
            label: "Ghostty",
            text: nil,
            executable: "/Applications/Ghostty.app/Contents/MacOS/ghostty",
            arguments: ["--working-directory={{path}}"],
            tooltip: nil,
            autoSend: nil
        )
        if case .launchProcess(let path, let arguments) = item.action {
            XCTAssertEqual(path, "/Applications/Ghostty.app/Contents/MacOS/ghostty")
            XCTAssertEqual(arguments, ["--working-directory={{path}}"])
        } else {
            XCTFail("Expected .launchProcess action, got \(String(describing: item.action))")
        }
    }
}
