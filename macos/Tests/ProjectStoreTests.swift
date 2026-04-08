import XCTest
@testable import Ghostty

final class ProjectStoreTests: XCTestCase {
    var store: ProjectStore!
    var tempFile: URL!

    override func setUp() {
        tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-projects-\(UUID().uuidString).json")
        store = ProjectStore(filePath: tempFile.path)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempFile)
    }

    func testStartsEmpty() {
        XCTAssertTrue(store.projects.isEmpty)
    }

    func testAddProject() {
        store.addProject(path: "/tmp/test-project")
        XCTAssertEqual(store.projects.count, 1)
        XCTAssertEqual(store.projects[0].path, "/tmp/test-project")
        XCTAssertEqual(store.projects[0].name, "test-project")
    }

    func testAddDuplicateIsIgnored() {
        store.addProject(path: "/tmp/test-project")
        store.addProject(path: "/tmp/test-project")
        XCTAssertEqual(store.projects.count, 1)
    }

    func testRemoveProject() {
        store.addProject(path: "/tmp/test-project")
        store.removeProject(path: "/tmp/test-project")
        XCTAssertTrue(store.projects.isEmpty)
    }

    func testPersistsToJSON() {
        store.addProject(path: "/tmp/project-a")
        store.addProject(path: "/tmp/project-b")

        let store2 = ProjectStore(filePath: tempFile.path)
        XCTAssertEqual(store2.projects.count, 2)
        XCTAssertEqual(store2.projects[0].path, "/tmp/project-a")
        XCTAssertEqual(store2.projects[1].path, "/tmp/project-b")
    }

    func testSetActive() {
        store.addProject(path: "/tmp/project-a")
        store.setActive("/tmp/project-a", active: true)
        XCTAssertEqual(store.projects[0].state, .activeBackground)
    }

    func testSetVisible() {
        store.addProject(path: "/tmp/project-a")
        store.addProject(path: "/tmp/project-b")
        store.setActive("/tmp/project-a", active: true)
        store.setActive("/tmp/project-b", active: true)
        store.setVisible("/tmp/project-a")
        XCTAssertEqual(store.projects[0].state, .activeVisible)
        XCTAssertEqual(store.projects[1].state, .activeBackground)
    }

    func testMigratesLegacyStringFormat() throws {
        let paths = ["/tmp/project-a", "/tmp/project-b"]
        let data = try JSONEncoder().encode(paths)
        try data.write(to: tempFile)

        let migrated = ProjectStore(filePath: tempFile.path)
        XCTAssertEqual(migrated.projects.count, 2)
        XCTAssertEqual(migrated.projects[0].path, "/tmp/project-a")
        XCTAssertEqual(migrated.projects[1].path, "/tmp/project-b")
        XCTAssertNil(migrated.projects[0].binary)
        XCTAssertNil(migrated.projects[1].binary)
    }

    func testSetBinary() {
        store.addProject(path: "/tmp/project-a")
        store.setBinary("/tmp/project-a", binary: .opencode)
        XCTAssertEqual(store.projects[0].binary, .opencode)
    }

    func testSetBinaryToNil() {
        store.addProject(path: "/tmp/project-a")
        store.setBinary("/tmp/project-a", binary: .codex)
        store.setBinary("/tmp/project-a", binary: nil)
        XCTAssertNil(store.projects[0].binary)
    }

    func testPersistsBinaryPreference() {
        store.addProject(path: "/tmp/project-a")
        store.setBinary("/tmp/project-a", binary: .codex)

        let reloaded = ProjectStore(filePath: tempFile.path)
        XCTAssertEqual(reloaded.projects[0].binary, .codex)
    }

    func testLegacyFormatSurvivesRoundTrip() throws {
        let paths = ["/tmp/project-a"]
        let data = try JSONEncoder().encode(paths)
        try data.write(to: tempFile)

        let migrated = ProjectStore(filePath: tempFile.path)
        migrated.addProject(path: "/tmp/project-b")

        let reloaded = ProjectStore(filePath: tempFile.path)
        XCTAssertEqual(reloaded.projects.count, 2)
        XCTAssertEqual(reloaded.projects[0].path, "/tmp/project-a")
        XCTAssertEqual(reloaded.projects[1].path, "/tmp/project-b")
    }

    func testSetBinaryForUnknownPathIsNoOp() {
        store.addProject(path: "/tmp/project-a")
        store.setBinary("/tmp/nonexistent", binary: .codex)
        XCTAssertNil(store.projects[0].binary)
    }

    func testMoveProjectForward() {
        store.addProject(path: "/tmp/project-a")
        store.addProject(path: "/tmp/project-b")
        store.addProject(path: "/tmp/project-c")
        store.moveProject(from: 0, to: 2)
        XCTAssertEqual(store.projects.map(\.path), [
            "/tmp/project-b", "/tmp/project-c", "/tmp/project-a"
        ])
    }

    func testMoveProjectBackward() {
        store.addProject(path: "/tmp/project-a")
        store.addProject(path: "/tmp/project-b")
        store.addProject(path: "/tmp/project-c")
        store.moveProject(from: 2, to: 0)
        XCTAssertEqual(store.projects.map(\.path), [
            "/tmp/project-c", "/tmp/project-a", "/tmp/project-b"
        ])
    }

    func testMoveProjectSameIndex() {
        store.addProject(path: "/tmp/project-a")
        store.addProject(path: "/tmp/project-b")
        store.moveProject(from: 0, to: 0)
        XCTAssertEqual(store.projects.map(\.path), [
            "/tmp/project-a", "/tmp/project-b"
        ])
    }

    func testMoveProjectOutOfBounds() {
        store.addProject(path: "/tmp/project-a")
        store.moveProject(from: 0, to: 5)
        XCTAssertEqual(store.projects.map(\.path), ["/tmp/project-a"])
    }

    func testReplaceProjects() {
        store.addProject(path: "/tmp/project-a")
        store.addProject(path: "/tmp/project-b")
        store.addProject(path: "/tmp/project-c")

        let reordered = [
            Project(path: "/tmp/project-c"),
            Project(path: "/tmp/project-a"),
        ]
        store.replaceProjects(reordered)

        XCTAssertEqual(store.projects.count, 2)
        XCTAssertEqual(store.projects.map(\.path), ["/tmp/project-c", "/tmp/project-a"])
    }

    func testReplaceProjectsPersists() {
        store.addProject(path: "/tmp/project-a")
        store.addProject(path: "/tmp/project-b")

        let reordered = [
            Project(path: "/tmp/project-b"),
            Project(path: "/tmp/project-a"),
        ]
        store.replaceProjects(reordered)

        let reloaded = ProjectStore(filePath: tempFile.path)
        XCTAssertEqual(reloaded.projects.map(\.path), ["/tmp/project-b", "/tmp/project-a"])
    }

    func testReplaceProjectsPreservesBinary() {
        store.addProject(path: "/tmp/project-a")
        store.setBinary("/tmp/project-a", binary: .codex)
        store.addProject(path: "/tmp/project-b")

        let reordered = [
            Project(path: "/tmp/project-b"),
            Project(path: "/tmp/project-a"),
        ]
        store.replaceProjects(reordered)

        XCTAssertEqual(store.projects[1].binary, .codex)
    }
}
