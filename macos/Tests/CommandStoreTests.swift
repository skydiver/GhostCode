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

    func testMissingFileReturnsDefaults() {
        let store = CommandStore(filePath: "/nonexistent/commands.json")
        XCTAssertFalse(store.sections.isEmpty, "Should provide default sections")
    }

    func testMalformedJSONReturnsDefaults() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-commands-\(UUID().uuidString).json")
        try "{ invalid json".data(using: .utf8)!.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let store = CommandStore(filePath: tempFile.path)
        XCTAssertFalse(store.sections.isEmpty, "Should fallback to defaults")
    }
}
