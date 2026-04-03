import XCTest
@testable import Ghostty

final class GhostCodeConfigTests: XCTestCase {
    // MARK: - SupportedBinary

    func testCommandNames() {
        XCTAssertEqual(SupportedBinary.claude.commandName, "claude")
        XCTAssertEqual(SupportedBinary.codex.commandName, "codex")
        XCTAssertEqual(SupportedBinary.opencode.commandName, "opencode")
    }

    func testDisplayNames() {
        XCTAssertEqual(SupportedBinary.claude.displayName, "Claude Code")
        XCTAssertEqual(SupportedBinary.codex.displayName, "Codex")
        XCTAssertEqual(SupportedBinary.opencode.displayName, "OpenCode")
    }

    func testResumeArgs() {
        XCTAssertEqual(SupportedBinary.claude.resumeArg, "--continue")
        XCTAssertNil(SupportedBinary.codex.resumeArg)
        XCTAssertNil(SupportedBinary.opencode.resumeArg)
    }

    func testSessionInfoSupport() {
        XCTAssertTrue(SupportedBinary.claude.supportsSessionInfo)
        XCTAssertFalse(SupportedBinary.codex.supportsSessionInfo)
        XCTAssertFalse(SupportedBinary.opencode.supportsSessionInfo)
    }

    func testCodableRoundTrip() throws {
        for binary in SupportedBinary.allCases {
            let data = try JSONEncoder().encode(binary)
            let decoded = try JSONDecoder().decode(SupportedBinary.self, from: data)
            XCTAssertEqual(decoded, binary)
        }
    }

    func testAllCasesCount() {
        XCTAssertEqual(SupportedBinary.allCases.count, 3)
    }

    // MARK: - AppConfig

    func testLoadAppConfigMissingFile() {
        let config = GhostCodeConfig.loadAppConfig(from: "/nonexistent/config.json")
        XCTAssertEqual(config.defaultBinary, .claude)
    }

    func testLoadAppConfigValidFile() throws {
        let json = #"{ "defaultBinary": "codex" }"#
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-config-\(UUID().uuidString).json")
        try json.data(using: .utf8)!.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let config = GhostCodeConfig.loadAppConfig(from: tempFile.path)
        XCTAssertEqual(config.defaultBinary, .codex)
    }

    func testLoadAppConfigMalformedFile() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-config-\(UUID().uuidString).json")
        try "{ invalid json".data(using: .utf8)!.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let config = GhostCodeConfig.loadAppConfig(from: tempFile.path)
        XCTAssertEqual(config.defaultBinary, .claude)
    }
}
