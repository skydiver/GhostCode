import XCTest
@testable import Ghostty

final class GitStatusProviderTests: XCTestCase {
    func testParseBranchName() {
        let output = "## main...origin/main"
        let status = GitStatusProvider.parseGitStatus(
            statusOutput: output,
            aheadBehind: ""
        )
        XCTAssertEqual(status?.branch, "main")
    }

    func testParseCleanRepo() {
        let output = "## feat/sidebar...origin/feat/sidebar"
        let status = GitStatusProvider.parseGitStatus(
            statusOutput: output,
            aheadBehind: ""
        )
        XCTAssertEqual(status?.branch, "feat/sidebar")
        XCTAssertFalse(status?.isDirty ?? true)
        XCTAssertEqual(status?.changedFileCount, 0)
    }

    func testParseDirtyRepo() {
        let output = "## main\n M Sources/file1.swift\nM  Sources/file2.swift\n?? newfile.swift"
        let status = GitStatusProvider.parseGitStatus(
            statusOutput: output,
            aheadBehind: ""
        )
        XCTAssertEqual(status?.branch, "main")
        XCTAssertTrue(status?.isDirty ?? false)
        XCTAssertEqual(status?.changedFileCount, 3)
    }

    func testParseAheadBehind() {
        let output = "## main...origin/main [ahead 2, behind 1]"
        let status = GitStatusProvider.parseGitStatus(
            statusOutput: output,
            aheadBehind: "2\t1\n"
        )
        XCTAssertEqual(status?.ahead, 2)
        XCTAssertEqual(status?.behind, 1)
    }

    func testParseDottedBranchName() {
        let output = "## release/1.0...origin/release/1.0"
        let status = GitStatusProvider.parseGitStatus(
            statusOutput: output,
            aheadBehind: ""
        )
        XCTAssertEqual(status?.branch, "release/1.0")
    }

    func testParseNonGitDirectory() {
        let status = GitStatusProvider.parseGitStatus(
            statusOutput: "",
            aheadBehind: ""
        )
        XCTAssertNil(status)
    }

    // MARK: - runGit hardening

    func testGitProcessDisablesFsmonitorAndOptionalLocks() {
        let process = GitStatusProvider.makeGitProcess(["status"], in: "/tmp/project")
        XCTAssertEqual(
            process.arguments,
            ["-c", "core.fsmonitor=false", "-C", "/tmp/project", "status"]
        )
        XCTAssertEqual(process.environment?["GIT_OPTIONAL_LOCKS"], "0")
        XCTAssertEqual(
            process.environment?["PATH"],
            ProcessInfo.processInfo.environment["PATH"]
        )
    }

    func testFetchStatusDoesNotRunRepoFsmonitorHook() async throws {
        let repo = try makeRepository()
        let marker = repo.deletingLastPathComponent().appendingPathComponent("fsmonitor-ran")
        let hook = repo.deletingLastPathComponent().appendingPathComponent("fsmonitor-hook.sh")
        try "#!/bin/sh\ntouch '\(marker.path)'\n".write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        try git(["config", "core.fsmonitor", hook.path], in: repo)

        let status = await GitStatusProvider.fetchStatus(for: repo.path)

        XCTAssertNotNil(status)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testFetchStatusReadsOutputLargerThanPipeBuffer() async throws {
        let repo = try makeRepository()
        // ~3000 porcelain lines of ~50 bytes overflow the 64 KiB pipe buffer.
        let fileCount = 3000
        let padding = String(repeating: "x", count: 40)
        for index in 0..<fileCount {
            let file = repo.appendingPathComponent("untracked-\(padding)-\(index)")
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }

        // A deadlocked runGit never resumes, so bound the wait instead of awaiting directly.
        let finished = expectation(description: "fetchStatus returned")
        var status: Project.GitStatus?
        Task {
            status = await GitStatusProvider.fetchStatus(for: repo.path)
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 15)

        XCTAssertEqual(status?.changedFileCount, fileCount)
    }

    // MARK: - gitHubURL

    func testGitHubURLFromHTTPSRemoteStripsTrailingGit() {
        XCTAssertEqual(gitHubURL("https://github.com/owner/repo.git"), "https://github.com/owner/repo")
    }

    func testGitHubURLAcceptsWWWHost() {
        XCTAssertEqual(gitHubURL("https://www.github.com/owner/repo"), "https://www.github.com/owner/repo")
    }

    func testGitHubURLFromSSHRemote() {
        XCTAssertEqual(gitHubURL("git@github.com:owner/repo.git"), "https://github.com/owner/repo")
    }

    func testGitHubURLKeepsGitInsideRepoName() {
        XCTAssertEqual(
            gitHubURL("https://github.com/owner/owner.github.io.git"),
            "https://github.com/owner/owner.github.io"
        )
        XCTAssertEqual(
            gitHubURL("git@github.com:owner/owner.github.io"),
            "https://github.com/owner/owner.github.io"
        )
    }

    func testGitHubURLDropsCredentials() {
        XCTAssertEqual(
            gitHubURL("https://user:token@github.com/owner/repo.git"),
            "https://github.com/owner/repo"
        )
    }

    func testGitHubURLRejectsGitHubInPathOnly() {
        XCTAssertNil(gitHubURL("https://evil.example/github.com"))
    }

    func testGitHubURLRejectsGitHubAsSubdomainOfOtherHost() {
        XCTAssertNil(gitHubURL("https://github.com.evil.example/x"))
    }

    func testGitHubURLRejectsNonHTTPSSchemes() {
        XCTAssertNil(gitHubURL("file:///tmp/github.com.app"))
        XCTAssertNil(gitHubURL("smb://127.0.0.1/github.com"))
        XCTAssertNil(gitHubURL("vnc://github.com/owner/repo"))
        XCTAssertNil(gitHubURL("http://github.com/owner/repo"))
    }

    func testGitHubURLNilWithoutRemote() {
        XCTAssertNil(gitHubURL(nil))
    }

    // MARK: - Helpers

    private func gitHubURL(_ remote: String?) -> String? {
        Project.GitStatus(
            branch: "main",
            isDirty: false,
            changedFileCount: 0,
            ahead: 0,
            behind: 0,
            remoteURL: remote
        ).gitHubURL?.absoluteString
    }

    /// Creates a repository with one commit in a fresh temporary directory.
    private func makeRepository() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitstatus-\(UUID().uuidString)")
        let repo = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        try git(["init", "-q"], in: repo)
        try "a\n".write(to: repo.appendingPathComponent("a"), atomically: true, encoding: .utf8)
        try git(["add", "a"], in: repo)
        try git(["-c", "user.name=test", "-c", "user.email=test@example.com", "commit", "-qm", "init"], in: repo)
        return repo
    }

    private func git(_ args: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(args.joined(separator: " ")) failed")
    }
}
