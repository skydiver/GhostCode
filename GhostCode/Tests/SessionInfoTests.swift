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
}
