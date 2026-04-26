import XCTest
@testable import Ghostty

final class CommandStoreTests: XCTestCase {
    func testLoadsFromJSON() throws {
        let json = """
        {
            "sections": [
                {
                    "name": "Commands",
                    "items": [
                        { "label": "/commit", "text": "/commit" },
                        { "label": "Fix tests", "text": "fix the failing tests" }
                    ]
                }
            ]
        }
        """
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-commands-\(UUID().uuidString).json")
        try json.data(using: .utf8)!.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let store = CommandStore(filePath: tempFile.path)
        XCTAssertEqual(store.sections.count, 1)
        XCTAssertEqual(store.sections[0].name, "Commands")
        XCTAssertEqual(store.sections[0].items.count, 2)
        XCTAssertEqual(store.sections[0].items[0].label, "/commit")
        XCTAssertEqual(store.sections[0].items[0].text, "/commit")
    }

    func testMissingFileReturnsEmpty() {
        let store = CommandStore(filePath: "/nonexistent/commands.jsonc")
        XCTAssertTrue(store.sections.isEmpty, "Should be empty when file cannot be created")
    }

    func testMalformedJSONReturnsEmpty() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-commands-\(UUID().uuidString).jsonc")
        try "{ invalid json".data(using: .utf8)!.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let store = CommandStore(filePath: tempFile.path)
        XCTAssertTrue(store.sections.isEmpty, "Should be empty on malformed JSON")
    }

    // MARK: - Tile sections

    func testTileSectionDecodesWithExecutableOnlyItems() throws {
        let json = """
        {
          "sections": [
            {
              "name": "Apps",
              "layout": "tiles",
              "items": [
                { "label": "VSCode", "executable": "/usr/local/bin/code" },
                { "label": "Tower",  "executable": "/Applications/Tower.app/Contents/MacOS/Tower" }
              ]
            }
          ]
        }
        """
        let store = try makeStore(with: json)
        XCTAssertEqual(store.sections.count, 1)
        XCTAssertEqual(store.sections[0].resolvedLayout, .tiles)
        XCTAssertEqual(store.sections[0].items.count, 2)
        XCTAssertEqual(store.sections[0].items[0].label, "VSCode")
        XCTAssertEqual(store.sections[0].items[0].executable, "/usr/local/bin/code")
        XCTAssertNil(store.sections[0].items[0].text)
    }

    func testFlowSectionStillWorksWithTextOnlyItems() throws {
        let json = """
        {
          "sections": [
            {
              "name": "Prompts",
              "layout": "flow",
              "items": [
                { "label": "Refactor", "text": "please refactor this" }
              ]
            }
          ]
        }
        """
        let store = try makeStore(with: json)
        XCTAssertEqual(store.sections[0].resolvedLayout, .flow)
        XCTAssertEqual(store.sections[0].items[0].text, "please refactor this")
        XCTAssertNil(store.sections[0].items[0].executable)
    }

    func testMixedSectionDecodesExecutablesInFlowLayout() throws {
        let json = """
        {
          "sections": [
            {
              "name": "Mixed",
              "layout": "flow",
              "items": [
                { "label": "VSCode", "executable": "/usr/local/bin/code" },
                { "label": "Refactor", "text": "please refactor" }
              ]
            }
          ]
        }
        """
        let store = try makeStore(with: json)
        XCTAssertEqual(store.sections[0].items.count, 2)
        XCTAssertEqual(store.sections[0].items[0].executable, "/usr/local/bin/code")
        XCTAssertEqual(store.sections[0].items[1].text, "please refactor")
    }

    func testItemWithBothTextAndExecutableFailsDecode() throws {
        let json = """
        {
          "sections": [
            {
              "name": "Bad",
              "items": [
                { "label": "Both", "text": "hi", "executable": "/bin/echo" }
              ]
            }
          ]
        }
        """
        let store = try makeStore(with: json)
        XCTAssertTrue(store.sections.isEmpty,
                      "Should fail to load when an item has both text and executable")
    }

    func testItemWithNeitherTextNorExecutableFailsDecode() throws {
        let json = """
        {
          "sections": [
            {
              "name": "Bad",
              "items": [
                { "label": "Empty" }
              ]
            }
          ]
        }
        """
        let store = try makeStore(with: json)
        XCTAssertTrue(store.sections.isEmpty,
                      "Should fail to load when an item has neither text nor executable")
    }

    func testItemWithRelativeExecutablePathFailsDecode() throws {
        let json = """
        {
          "sections": [
            {
              "name": "Bad",
              "items": [
                { "label": "Relative", "executable": "code" }
              ]
            }
          ]
        }
        """
        let store = try makeStore(with: json)
        XCTAssertTrue(store.sections.isEmpty,
                      "Should fail to load when executable is not an absolute path")
    }

    // MARK: - Icon field

    func testItemDecodesIconFieldWhenPresent() throws {
        let json = """
        {
          "sections": [
            {
              "name": "Apps",
              "layout": "tiles",
              "items": [
                { "label": "VSCode", "executable": "/usr/local/bin/code", "icon": "hammer.fill" }
              ]
            }
          ]
        }
        """
        let store = try makeStore(with: json)
        XCTAssertEqual(store.sections[0].items[0].icon, "hammer.fill")
    }

    func testItemIconIsNilWhenAbsent() throws {
        let json = """
        {
          "sections": [
            {
              "name": "Commands",
              "items": [
                { "label": "/commit", "text": "/commit" }
              ]
            }
          ]
        }
        """
        let store = try makeStore(with: json)
        XCTAssertNil(store.sections[0].items[0].icon)
    }

    // MARK: - Icon position field

    func testIconPositionDecodesAllFourValues() throws {
        let json = """
        {
          "sections": [
            {
              "name": "Apps",
              "layout": "tiles",
              "items": [
                { "label": "Top",    "executable": "/bin/echo", "iconPosition": "top" },
                { "label": "Bottom", "executable": "/bin/echo", "iconPosition": "bottom" },
                { "label": "Left",   "executable": "/bin/echo", "iconPosition": "left" },
                { "label": "Right",  "executable": "/bin/echo", "iconPosition": "right" }
              ]
            }
          ]
        }
        """
        let store = try makeStore(with: json)
        XCTAssertEqual(store.sections[0].items[0].iconPosition, .top)
        XCTAssertEqual(store.sections[0].items[1].iconPosition, .bottom)
        XCTAssertEqual(store.sections[0].items[2].iconPosition, .left)
        XCTAssertEqual(store.sections[0].items[3].iconPosition, .right)
    }

    func testIconPositionIsNilWhenAbsent() throws {
        let json = """
        {
          "sections": [
            { "name": "Apps", "items": [ { "label": "A", "text": "a" } ] }
          ]
        }
        """
        let store = try makeStore(with: json)
        XCTAssertNil(store.sections[0].items[0].iconPosition)
    }

    // MARK: - resolvedIconPosition(for:)

    func testTilesDefaultPositionIsTop() {
        let item = CommandItem(label: "X", text: "x")
        XCTAssertEqual(item.resolvedIconPosition(for: .tiles), .top)
    }

    func testTilesHonorAllFourPositions() {
        for pos in [IconPosition.top, .bottom, .left, .right] {
            let item = CommandItem(label: "X", text: "x", iconPosition: pos)
            XCTAssertEqual(item.resolvedIconPosition(for: .tiles), pos)
        }
    }

    func testFlowDefaultPositionIsLeft() {
        let item = CommandItem(label: "X", text: "x")
        XCTAssertEqual(item.resolvedIconPosition(for: .flow), .left)
    }

    func testFlowHonorsRight() {
        let item = CommandItem(label: "X", text: "x", iconPosition: .right)
        XCTAssertEqual(item.resolvedIconPosition(for: .flow), .right)
    }

    func testFlowIgnoresTopAndBottom() {
        for pos in [IconPosition.top, .bottom] {
            let item = CommandItem(label: "X", text: "x", iconPosition: pos)
            XCTAssertEqual(item.resolvedIconPosition(for: .flow), .left,
                           "\(pos) should fall back to .left in flow layout")
        }
    }

    func testListDefaultPositionIsLeft() {
        let item = CommandItem(label: "X", text: "x")
        XCTAssertEqual(item.resolvedIconPosition(for: .list), .left)
    }

    func testListIgnoresTopAndBottom() {
        for pos in [IconPosition.top, .bottom] {
            let item = CommandItem(label: "X", text: "x", iconPosition: pos)
            XCTAssertEqual(item.resolvedIconPosition(for: .list), .left,
                           "\(pos) should fall back to .left in list layout")
        }
    }

    func testListHonorsRight() {
        let item = CommandItem(label: "X", text: "x", iconPosition: .right)
        XCTAssertEqual(item.resolvedIconPosition(for: .list), .right)
    }

    func testDefaultJSONCTemplateIsValid() throws {
        // Forces creation of the bundled default file in a clean temp dir,
        // then verifies it parses without errors and produces the expected sections.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-default-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempDir)
        }
        let path = tempDir.appendingPathComponent("commands.jsonc").path

        let store = CommandStore(filePath: path)

        XCTAssertFalse(store.sections.isEmpty,
                       "Default template should produce at least one section after creation")
        // Apps section is the new addition; ensure it loads (with empty items, since
        // the example tile entries are commented out).
        XCTAssertTrue(store.sections.contains { $0.name == "Apps" && $0.resolvedLayout == .tiles },
                      "Default template should contain an 'Apps' tile section")
    }

    // MARK: - Helpers

    private func makeStore(with json: String) throws -> CommandStore {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-commands-\(UUID().uuidString).jsonc")
        try json.data(using: .utf8)!.write(to: tempFile)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempFile)
        }
        return CommandStore(filePath: tempFile.path)
    }
}
