import XCTest
@testable import Ghostty

final class SessionInfoTests: XCTestCase {
    func testSummaryWithoutSessions() {
        let info = SessionInfoProvider.SessionInfo(count: 0, lastDate: nil)
        XCTAssertEqual(info.summary(relativeTo: Date()), "No previous sessions")
    }

    func testSummaryWithUnknownLastDate() {
        // Every stat failed, e.g. the files were rotated between listing and stat.
        let info = SessionInfoProvider.SessionInfo(count: 2, lastDate: nil)
        XCTAssertEqual(info.summary(relativeTo: Date()), "2 sessions")
    }

    func testSummaryWithLastDate() {
        let now = Date()
        let info = SessionInfoProvider.SessionInfo(count: 1, lastDate: now.addingTimeInterval(-3600))
        XCTAssertTrue(info.summary(relativeTo: now).hasPrefix("1 session · last "))
    }

    // MARK: - Claude Code project directory names

    func testDirectoryNameReplacesEveryNonAlphanumeric() {
        XCTAssertEqual(
            SessionInfoProvider.directoryName(for: "/Users/a/.config/my_app dir"),
            "-Users-a--config-my-app-dir"
        )
    }

    func testDirectoryNameCountsUTF16Units() {
        // Claude Code replaces per UTF-16 unit: "é" is one, an emoji is two.
        XCTAssertEqual(SessionInfoProvider.directoryName(for: "/é/😀"), "-----")
    }

    func testSessionsDirectoryFindsExactName() throws {
        let root = try makeRoot()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("-tmp-my-app"), withIntermediateDirectories: false)

        XCTAssertEqual(
            SessionInfoProvider.sessionsDirectory(for: "/tmp/my.app", in: root.path),
            root.appendingPathComponent("-tmp-my-app").path
        )
    }

    func testSessionsDirectoryFindsHashedNameForLongPath() throws {
        let root = try makeRoot()
        let longPath = "/" + String(repeating: "a", count: 250)
        let truncated = "-" + String(repeating: "a", count: 199)
        let hashed = root.appendingPathComponent("\(truncated)-1x2y3z")
        try FileManager.default.createDirectory(at: hashed, withIntermediateDirectories: false)

        XCTAssertEqual(SessionInfoProvider.sessionsDirectory(for: longPath, in: root.path), hashed.path)
    }

    func testSessionsDirectoryNilWhenMissing() throws {
        XCTAssertNil(SessionInfoProvider.sessionsDirectory(for: "/tmp/none", in: try makeRoot().path))
    }

    // MARK: - Display path

    func testAbbreviatesHomeDirectory() {
        XCTAssertEqual(ProjectPathFormatter.abbreviatingHome("/Users/martin/src/x", home: "/Users/martin"), "~/src/x")
        XCTAssertEqual(ProjectPathFormatter.abbreviatingHome("/Users/martin", home: "/Users/martin"), "~")
    }

    func testDoesNotAbbreviateSiblingOfHome() {
        XCTAssertEqual(
            ProjectPathFormatter.abbreviatingHome("/Users/martinez/x", home: "/Users/martin"),
            "/Users/martinez/x"
        )
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("claude-projects-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
}
