import XCTest
import AppKit
@testable import Ghostty

final class KeyShortcutRouterTests: XCTestCase {
    private let none = KeyShortcutRouter.Context(hasActiveProject: false, tabCount: 0)
    private let oneTab = KeyShortcutRouter.Context(hasActiveProject: true, tabCount: 1)
    private let threeTabs = KeyShortcutRouter.Context(hasActiveProject: true, tabCount: 3)

    private func route(
        _ characters: String?,
        keyCode: UInt16 = 0,
        _ modifiers: NSEvent.ModifierFlags,
        _ context: KeyShortcutRouter.Context
    ) -> KeyShortcut? {
        KeyShortcutRouter.route(keyCode: keyCode, characters: characters, modifiers: modifiers, context: context)
    }

    // MARK: - Sidebars

    func testCmdShiftLTogglesLeftSidebarEvenWithoutProject() {
        XCTAssertEqual(route("l", [.command, .shift], none), .toggleLeftSidebar)
        XCTAssertEqual(route("L", [.command, .shift], none), .toggleLeftSidebar)
    }

    func testCmdShiftRTogglesRightSidebar() {
        XCTAssertEqual(route("R", [.command, .shift], none), .toggleRightSidebar)
    }

    // MARK: - Tabs

    func testCmdShiftBracketsCycleTabsWhenThereAreSeveral() {
        XCTAssertEqual(route("{", keyCode: 33, [.command, .shift], threeTabs), .previousTab)
        XCTAssertEqual(route("}", keyCode: 30, [.command, .shift], threeTabs), .nextTab)
    }

    func testCmdShiftBracketsPassThroughWithOneTab() {
        XCTAssertNil(route("{", keyCode: 33, [.command, .shift], oneTab))
        XCTAssertNil(route("}", keyCode: 30, [.command, .shift], none))
    }

    func testCmdDigitSelectsTab() {
        XCTAssertEqual(route("2", [.command], threeTabs), .selectTab(index: 1))
        XCTAssertEqual(route("7", [.command], threeTabs), .selectTab(index: 2), "clamped to the last tab")
        XCTAssertEqual(route("9", [.command], threeTabs), .selectTab(index: 2), "9 is always the last tab")
    }

    func testCmdDigitPassesThroughWithoutTabs() {
        XCTAssertNil(route("1", [.command], none))
        XCTAssertNil(route("1", [.command], KeyShortcutRouter.Context(hasActiveProject: true, tabCount: 0)))
    }

    func testCmdZeroPassesThrough() {
        XCTAssertNil(route("0", [.command], threeTabs))
    }

    func testCmdWClosesTab() {
        XCTAssertEqual(route("w", [.command], oneTab), .closeActiveTab)
        XCTAssertNil(route("w", [.command], none))
    }

    func testCmdTOpensShellTab() {
        XCTAssertEqual(route("t", [.command], KeyShortcutRouter.Context(hasActiveProject: true, tabCount: 0)), .newShellTab)
        XCTAssertNil(route("t", [.command], none))
    }

    // MARK: - Full screen

    func testCmdEnterTogglesFullScreen() {
        XCTAssertEqual(route("\r", keyCode: 36, [.command], oneTab), .toggleFullScreen)
        XCTAssertNil(route("\r", keyCode: 36, [.command], none))
    }

    func testCmdCtrlFTogglesFullScreen() {
        XCTAssertEqual(route("f", [.command, .control], oneTab), .toggleFullScreen)
    }

    // MARK: - Swallowed Ghostty shortcuts

    func testGhosttyWindowAndSplitShortcutsAreSwallowedInProjects() {
        let swallowed: [(String?, UInt16, NSEvent.ModifierFlags)] = [
            ("D", 0, [.command, .shift]),        // new_split:down
            ("W", 0, [.command, .shift]),        // close_window
            ("P", 0, [.command, .shift]),        // command palette
            ("i", 0, [.command, .option]),       // inspector
            ("n", 0, [.command]),                // new_window
            ("d", 0, [.command]),                // new_split:right
            ("[", 0, [.command]),                // goto_split
            ("]", 0, [.command]),
            ("w", 0, [.command, .shift, .option]), // close_all_windows
            (nil, 126, [.command, .option]),     // goto_split up
            (nil, 123, [.command, .control]),    // resize_split left
            ("=", 0, [.command, .control]),      // equalize_splits
        ]
        for (characters, keyCode, modifiers) in swallowed {
            XCTAssertEqual(
                route(characters, keyCode: keyCode, modifiers, oneTab), .swallow,
                "\(characters ?? "keyCode \(keyCode)") \(modifiers)"
            )
            XCTAssertNil(
                route(characters, keyCode: keyCode, modifiers, none),
                "passes through without a project: \(characters ?? "keyCode \(keyCode)")"
            )
        }
    }

    // MARK: - Pass-through

    func testUnrelatedKeysPassThrough() {
        XCTAssertNil(route("c", [.command], oneTab))
        XCTAssertNil(route("a", [], oneTab))
        XCTAssertNil(route("l", [.command], oneTab))
    }

    func testDeviceDependentModifierBitsAreIgnored() {
        let withCapsLock: NSEvent.ModifierFlags = [.command, .capsLock]
        XCTAssertNil(route("w", withCapsLock, oneTab), "Caps Lock is a distinct combination, as before")
        let rawBits = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | 0x8)
        XCTAssertEqual(route("w", rawBits, oneTab), .closeActiveTab)
    }
}
