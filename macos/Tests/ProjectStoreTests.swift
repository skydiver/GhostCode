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
}
