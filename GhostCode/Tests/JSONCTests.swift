import XCTest
@testable import Ghostty

final class JSONCTests: XCTestCase {
    // MARK: - Comment Stripping

    func testStripsNothing() throws {
        let input = #"{"key": "value"}"#
        XCTAssertEqual(try JSONC.normalize(input), input)
    }

    func testStripsSingleLineComment() throws {
        let input = """
        {
            // this is a comment
            "key": "value"
        }
        """
        let result = try JSONC.normalize(input)
        XCTAssertFalse(result.contains("//"))
        XCTAssertTrue(result.contains("\"key\": \"value\""))
    }

    func testStripsMultiLineComment() throws {
        let input = """
        {
            /* this is
               a multi-line comment */
            "key": "value"
        }
        """
        let result = try JSONC.normalize(input)
        XCTAssertFalse(result.contains("/*"))
        XCTAssertFalse(result.contains("*/"))
        XCTAssertTrue(result.contains("\"key\": \"value\""))
    }

    func testPreservesCommentsInsideStrings() throws {
        let input = #"{"url": "http://example.com", "note": "/* not a comment */"}"#
        XCTAssertEqual(try JSONC.normalize(input), input)
    }

    func testPreservesSlashSlashInsideStrings() throws {
        let input = #"{"path": "C:\\Users\\test", "url": "http://x.com"}"#
        XCTAssertEqual(try JSONC.normalize(input), input)
    }

    func testStripsInlineComment() throws {
        let input = """
        {
            "key": "value" // inline comment
        }
        """
        let result = try JSONC.normalize(input)
        XCTAssertFalse(result.contains("inline"))
        XCTAssertTrue(result.contains("\"value\""))
    }

    func testStripsMultipleCommentStyles() throws {
        let input = """
        {
            // line comment
            "a": 1, /* block */ "b": 2
        }
        """
        let result = try JSONC.normalize(input)
        XCTAssertFalse(result.contains("line comment"))
        XCTAssertFalse(result.contains("block"))
        XCTAssertTrue(result.contains("\"a\": 1,"))
        XCTAssertTrue(result.contains("\"b\": 2"))
    }

    func testHandlesEscapedQuotesInStrings() throws {
        let input = #"{"msg": "he said \"// hello\"", "key": 1}"#
        let result = try JSONC.normalize(input)
        XCTAssertEqual(result, input, "Escaped quotes should not break string tracking")
    }

    func testEmptyInput() throws {
        XCTAssertEqual(try JSONC.normalize(""), "")
    }

    func testCommentOnly() throws {
        XCTAssertEqual(try JSONC.normalize("// just a comment").trimmingCharacters(in: .whitespaces), "")
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

    // MARK: - normalize (comments + trailing commas)

    func testNormalizeRemovesTrailingCommaInArray() throws {
        XCTAssertEqual(try JSONC.normalize("[1, 2,]"), "[1, 2]")
    }

    func testNormalizeRemovesTrailingCommaInObjectAcrossCommentAndNewline() throws {
        XCTAssertEqual(try JSONC.normalize("{\"a\": 1, // last\n}"), "{\"a\": 1 \n}")
    }

    func testNormalizeKeepsSeparatorCommas() throws {
        XCTAssertEqual(try JSONC.normalize("[1, /* c */ 2]"), "[1,  2]")
    }

    func testNormalizeKeepsCommasInsideStrings() throws {
        XCTAssertEqual(try JSONC.normalize("[\"a,]\", \"b,}\"]"), "[\"a,]\", \"b,}\"]")
    }

    func testNormalizeStripsComments() throws {
        XCTAssertEqual(try JSONC.normalize("{ /* a */ \"k\": 1 } // b"), "{  \"k\": 1 } ")
    }

    func testNormalizeRejectsUnterminatedBlockComment() {
        XCTAssertThrowsError(try JSONC.normalize("{\n\n  /* never closed\n\"k\": 1 }")) { error in
            XCTAssertEqual(error as? JSONC.ParseError, .unterminatedComment(line: 3))
        }
    }

    func testDecodeAcceptsTrailingCommas() throws {
        let jsonc = """
        {
            "sections": [
                { "name": "A", "items": [{ "label": "x", "text": "x", },], },
            ],
        }
        """
        let config = try JSONC.decode(CommandConfig.self, from: Data(jsonc.utf8))
        XCTAssertEqual(config.sections.first?.items.first?.label, "x")
    }
}
