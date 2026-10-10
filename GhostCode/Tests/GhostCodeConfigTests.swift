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

    // MARK: - resolveCommand

    func testResolveCommandReturnsNilForUnknownCommand() async {
        let path = await GhostCodeConfig.resolveCommand("ghostcode-missing-\(UUID().uuidString)")
        XCTAssertNil(path)
    }

    func testResolveCommandReturnsAbsolutePathForKnownCommand() async {
        let path = await GhostCodeConfig.resolveCommand("ls")
        XCTAssertEqual(path.map { URL(fileURLWithPath: $0).lastPathComponent }, "ls")
        XCTAssertEqual(path?.hasPrefix("/"), true)
    }

    func testResolveCommandGivesUpOnHangingLoginShell() async throws {
        let hangingShell = try makeExecutable(named: "hanging-shell", script: "#!/bin/sh\nexec /bin/sleep 30\n")
        let start = Date()

        let path = await GhostCodeConfig.resolveCommand("ls", shell: hangingShell.path, timeout: 0.5)

        XCTAssertNil(path)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testValidatedExecutablePathAcceptsSingleLineAbsoluteExecutable() throws {
        let executable = try makeExecutable(named: "tool")
        XCTAssertEqual(
            GhostCodeConfig.validatedExecutablePath(fromShellOutput: "\(executable.path)\n"),
            executable.path
        )
    }

    func testValidatedExecutablePathRejectsBareName() {
        XCTAssertNil(GhostCodeConfig.validatedExecutablePath(fromShellOutput: "ls\n"))
    }

    func testValidatedExecutablePathRejectsAliasOutput() {
        XCTAssertNil(GhostCodeConfig.validatedExecutablePath(fromShellOutput: "alias claude='/bin/ls'\n"))
    }

    func testValidatedExecutablePathRejectsMultipleLines() {
        XCTAssertNil(GhostCodeConfig.validatedExecutablePath(fromShellOutput: "/bin/ls\n/bin/echo\n"))
    }

    func testValidatedExecutablePathRejectsEmptyOutput() {
        XCTAssertNil(GhostCodeConfig.validatedExecutablePath(fromShellOutput: "\n"))
    }

    func testValidatedExecutablePathRejectsNonExecutableFile() throws {
        let file = try makeExecutable(named: "plain", permissions: 0o644)
        XCTAssertNil(GhostCodeConfig.validatedExecutablePath(fromShellOutput: file.path))
    }

    func testValidatedExecutablePathRejectsDirectory() {
        XCTAssertNil(GhostCodeConfig.validatedExecutablePath(fromShellOutput: "/bin"))
    }

    func testValidatedExecutablePathRejectsMissingFile() {
        XCTAssertNil(GhostCodeConfig.validatedExecutablePath(fromShellOutput: "/nonexistent/claude"))
    }

    // MARK: - loginShellCommand

    func testLoginShellCommandPreservesPathWithShellMetacharacters() throws {
        let output = try temporaryDirectory().appendingPathComponent("args.txt")
        let executable = try makeExecutable(
            named: "it's a \"tool\" $HOME; touch pwned",
            script: "#!/bin/sh\nprintf '%s\\n' \"$0\" \"$@\" > '\(output.path)'\n"
        )

        let command = GhostCodeConfig.loginShellCommand(
            shell: "/bin/sh",
            executable: executable.path,
            arguments: ["--continue"]
        )
        // Ghostty runs the surface command through one `/bin/sh -c`.
        try runShell(command)

        let lines = try String(contentsOf: output, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        XCTAssertEqual(lines, [executable.path, "--continue", ""])
    }

    // MARK: - Helpers

    private func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostcode-config-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func makeExecutable(
        named name: String,
        script: String = "#!/bin/sh\n",
        permissions: Int = 0o755
    ) throws -> URL {
        let file = try temporaryDirectory().appendingPathComponent(name)
        try script.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: file.path)
        return file
    }

    private func runShell(_ command: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
