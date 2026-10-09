import Foundation

/// Utilities for parsing JSONC (JSON with Comments).
///
/// Swift's JSONDecoder only handles strict JSON. This enum provides a
/// comment-stripping pass so user-edited `.jsonc` config files can include
/// `//` single-line and `/* */` multi-line comments.
enum JSONC {
    /// Strips `//` and `/* */` comments from a JSONC string, returning valid JSON.
    ///
    /// Comments inside JSON string literals are preserved (e.g. `"http://example.com"`
    /// is not treated as containing a comment).
    static func stripComments(_ input: String) -> String {
        var result = ""
        result.reserveCapacity(input.count)
        var i = input.startIndex

        while i < input.endIndex {
            let c = input[i]

            // --- String literal: pass through verbatim ---
            if c == "\"" {
                result.append(c)
                i = input.index(after: i)
                while i < input.endIndex {
                    let sc = input[i]
                    if sc == "\\" {
                        result.append(sc)
                        i = input.index(after: i)
                        if i < input.endIndex {
                            result.append(input[i])
                            i = input.index(after: i)
                        }
                        continue
                    }
                    result.append(sc)
                    i = input.index(after: i)
                    if sc == "\"" { break }
                }
                continue
            }

            // --- Possible comment start ---
            if c == "/", input.index(after: i) < input.endIndex {
                let next = input[input.index(after: i)]

                // Single-line comment: skip to end of line
                if next == "/" {
                    i = input.index(i, offsetBy: 2)
                    while i < input.endIndex && input[i] != "\n" {
                        i = input.index(after: i)
                    }
                    continue
                }

                // Multi-line comment: skip to closing */
                if next == "*" {
                    i = input.index(i, offsetBy: 2)
                    while i < input.endIndex {
                        if input[i] == "*",
                           input.index(after: i) < input.endIndex,
                           input[input.index(after: i)] == "/" {
                            i = input.index(i, offsetBy: 2)
                            break
                        }
                        i = input.index(after: i)
                    }
                    continue
                }
            }

            // --- Regular character ---
            result.append(c)
            i = input.index(after: i)
        }

        return result
    }

    /// Decodes a JSONC string into a `Decodable` type, stripping comments first.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard let string = String(data: data, encoding: .utf8) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Data is not valid UTF-8")
            )
        }
        let stripped = stripComments(string)
        guard let jsonData = stripped.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Stripped JSONC produced invalid UTF-8")
            )
        }
        return try JSONDecoder().decode(type, from: jsonData)
    }
}
