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
}
