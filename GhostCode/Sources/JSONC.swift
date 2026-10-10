import Foundation

/// Utilities for parsing JSONC (JSON with Comments).
///
/// Swift's JSONDecoder only handles strict JSON. This enum provides a
/// normalizing pass so user-edited `.jsonc` config files can include
/// `//` single-line and `/* */` multi-line comments, and trailing commas.
enum JSONC {
    enum ParseError: Error, Equatable, LocalizedError {
        case unterminatedComment(line: Int)

        var errorDescription: String? {
            switch self {
            case .unterminatedComment(let line):
                return "The /* comment starting on line \(line) is never closed."
            }
        }
    }

    /// Strips `//` and `/* */` comments and trailing commas from a JSONC string,
    /// returning JSON. Comment markers and commas inside string literals are kept
    /// (e.g. `"http://example.com"` is not treated as containing a comment).
    ///
    /// A comma is held back until the next significant character: it is dropped
    /// when that character closes an array or object, and emitted otherwise.
    static func normalize(_ input: String) throws -> String {
        var result = ""
        result.reserveCapacity(input.count)
        var pendingComma = false
        var pendingWhitespace = ""
        var line = 1
        var i = input.startIndex

        /// Writes out a held comma (unless `next` closes a container) and the
        /// whitespace that followed it.
        func flushPending(before next: Character) {
            if pendingComma, next != "}", next != "]" {
                result.append(",")
            }
            result.append(pendingWhitespace)
            pendingComma = false
            pendingWhitespace = ""
        }

        while i < input.endIndex {
            let c = input[i]

            // --- String literal: pass through verbatim ---
            if c == "\"" {
                flushPending(before: c)
                result.append(c)
                i = input.index(after: i)
                while i < input.endIndex {
                    let sc = input[i]
                    if sc.isNewline { line += 1 }
                    result.append(sc)
                    i = input.index(after: i)
                    if sc == "\\" {
                        if i < input.endIndex {
                            result.append(input[i])
                            i = input.index(after: i)
                        }
                        continue
                    }
                    if sc == "\"" { break }
                }
                continue
            }

            // --- Possible comment start ---
            if c == "/", input.index(after: i) < input.endIndex {
                let next = input[input.index(after: i)]

                // Single-line comment: skip to end of line (the newline is kept)
                if next == "/" {
                    i = input.index(i, offsetBy: 2)
                    while i < input.endIndex && input[i] != "\n" {
                        i = input.index(after: i)
                    }
                    continue
                }

                // Multi-line comment: skip to closing */
                if next == "*" {
                    let startLine = line
                    i = input.index(i, offsetBy: 2)
                    var closed = false
                    while i < input.endIndex {
                        if input[i] == "*",
                           input.index(after: i) < input.endIndex,
                           input[input.index(after: i)] == "/" {
                            i = input.index(i, offsetBy: 2)
                            closed = true
                            break
                        }
                        if input[i].isNewline { line += 1 }
                        i = input.index(after: i)
                    }
                    guard closed else { throw ParseError.unterminatedComment(line: startLine) }
                    continue
                }
            }

            // --- Commas and whitespace: held while a comma is pending ---
            if c == "," {
                flushPending(before: c)
                pendingComma = true
            } else if c.isWhitespace {
                if c.isNewline { line += 1 }
                if pendingComma {
                    pendingWhitespace.append(c)
                } else {
                    result.append(c)
                }
            } else {
                flushPending(before: c)
                result.append(c)
            }
            i = input.index(after: i)
        }

        if pendingComma { result.append(",") }
        result.append(pendingWhitespace)
        return result
    }

    /// Decodes a JSONC string into a `Decodable` type, normalizing it first.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard let string = String(data: data, encoding: .utf8) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Data is not valid UTF-8")
            )
        }
        let stripped = try normalize(string)
        guard let jsonData = stripped.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Stripped JSONC produced invalid UTF-8")
            )
        }
        return try JSONDecoder().decode(type, from: jsonData)
    }
}
