import XCTest
@testable import Ghostty

final class JSONCTests: XCTestCase {
    // MARK: - Comment Stripping

    func testStripsNothing() {
        let input = #"{"key": "value"}"#
        XCTAssertEqual(JSONC.stripComments(input), input)
    }

    func testStripsSingleLineComment() {
        let input = """
        {
            // this is a comment
            "key": "value"
        }
        """
        let result = JSONC.stripComments(input)
        XCTAssertFalse(result.contains("//"))
        XCTAssertTrue(result.contains("\"key\": \"value\""))
    }

    func testStripsMultiLineComment() {
        let input = """
        {
            /* this is
               a multi-line comment */
            "key": "value"
        }
        """
        let result = JSONC.stripComments(input)
        XCTAssertFalse(result.contains("/*"))
        XCTAssertFalse(result.contains("*/"))
        XCTAssertTrue(result.contains("\"key\": \"value\""))
    }

    func testPreservesCommentsInsideStrings() {
        let input = #"{"url": "http://example.com", "note": "/* not a comment */"}"#
        XCTAssertEqual(JSONC.stripComments(input), input)
    }

    func testPreservesSlashSlashInsideStrings() {
        let input = #"{"path": "C:\\Users\\test", "url": "http://x.com"}"#
        XCTAssertEqual(JSONC.stripComments(input), input)
    }

    func testStripsInlineComment() {
        let input = """
        {
            "key": "value" // inline comment
        }
        """
        let result = JSONC.stripComments(input)
        XCTAssertFalse(result.contains("inline"))
        XCTAssertTrue(result.contains("\"value\""))
    }

    func testStripsMultipleCommentStyles() {
        let input = """
        {
            // line comment
            "a": 1, /* block */ "b": 2
        }
        """
        let result = JSONC.stripComments(input)
        XCTAssertFalse(result.contains("line comment"))
        XCTAssertFalse(result.contains("block"))
        XCTAssertTrue(result.contains("\"a\": 1,"))
        XCTAssertTrue(result.contains("\"b\": 2"))
    }

    func testHandlesEscapedQuotesInStrings() {
        let input = #"{"msg": "he said \"// hello\"", "key": 1}"#
        let result = JSONC.stripComments(input)
        XCTAssertEqual(result, input, "Escaped quotes should not break string tracking")
    }

    func testEmptyInput() {
        XCTAssertEqual(JSONC.stripComments(""), "")
    }

    func testCommentOnly() {
        XCTAssertEqual(JSONC.stripComments("// just a comment").trimmingCharacters(in: .whitespaces), "")
    }

    // MARK: - JSONC Decoding

    func testDecodeWithComments() throws {
        let jsonc = """
        {
            // The name field
            "name": "Test",
            /* layout can be "flow" or "list" */
            "value": 42
        }
        """
        struct Sample: Decodable {
            let name: String
            let value: Int
        }
        let result = try JSONC.decode(Sample.self, from: jsonc.data(using: .utf8)!)
        XCTAssertEqual(result.name, "Test")
        XCTAssertEqual(result.value, 42)
    }

    func testDecodeCommandConfig() throws {
        let jsonc = """
        {
            // Command palette config
            "sections": [
                {
                    "name": "Tools",
                    // Layout options: "flow" (default), "list"
                    "items": [
                        { "label": "/commit", "text": "/commit" }
                    ]
                }
            ]
        }
        """
        let config = try JSONC.decode(CommandConfig.self, from: jsonc.data(using: .utf8)!)
        XCTAssertEqual(config.sections.count, 1)
        XCTAssertEqual(config.sections[0].items[0].label, "/commit")
    }
}
