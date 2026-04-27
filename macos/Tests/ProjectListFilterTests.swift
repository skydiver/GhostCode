import XCTest
@testable import Ghostty

final class ProjectListFilterTests: XCTestCase {
    private func makeProjects() -> [Project] {
        [
            Project(path: "/tmp/a", state: .inactive),
            Project(path: "/tmp/b", state: .activeBackground),
            Project(path: "/tmp/c", state: .activeVisible),
        ]
    }

    func testAllReturnsEveryProject() {
        let result = ProjectListFilter.all.apply(to: makeProjects())
        XCTAssertEqual(result.map(\.path), ["/tmp/a", "/tmp/b", "/tmp/c"])
    }

    func testActiveExcludesInactive() {
        let result = ProjectListFilter.active.apply(to: makeProjects())
        XCTAssertEqual(result.map(\.path), ["/tmp/b", "/tmp/c"])
    }

    func testActiveOnEmptyListReturnsEmpty() {
        XCTAssertTrue(ProjectListFilter.active.apply(to: []).isEmpty)
    }

    func testActiveWithOnlyInactiveProjectsReturnsEmpty() {
        let projects = [
            Project(path: "/tmp/a", state: .inactive),
            Project(path: "/tmp/b", state: .inactive),
        ]
        XCTAssertTrue(ProjectListFilter.active.apply(to: projects).isEmpty)
    }

    func testRawValueIsStableForAppStorage() {
        XCTAssertEqual(ProjectListFilter.all.rawValue, "all")
        XCTAssertEqual(ProjectListFilter.active.rawValue, "active")
        XCTAssertEqual(ProjectListFilter(rawValue: "all"), .all)
        XCTAssertEqual(ProjectListFilter(rawValue: "active"), .active)
    }
}
