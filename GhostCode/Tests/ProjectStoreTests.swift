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

    // MARK: - Custom Name

    func testSetNameStoresOverride() {
        store.addProject(path: "/tmp/project-a")
        store.setName("/tmp/project-a", name: "My Foo")
        XCTAssertEqual(store.projects[0].customName, "My Foo")
        XCTAssertEqual(store.projects[0].name, "My Foo")
    }

    func testSetNameTrimsWhitespace() {
        store.addProject(path: "/tmp/project-a")
        store.setName("/tmp/project-a", name: "  Spaced Out   ")
        XCTAssertEqual(store.projects[0].customName, "Spaced Out")
    }

    func testSetNameEmptyResetsToFolder() {
        store.addProject(path: "/tmp/project-a")
        store.setName("/tmp/project-a", name: "Custom")
        store.setName("/tmp/project-a", name: "")
        XCTAssertNil(store.projects[0].customName)
        XCTAssertEqual(store.projects[0].name, "project-a")
    }

    func testSetNameWhitespaceOnlyResetsToFolder() {
        store.addProject(path: "/tmp/project-a")
        store.setName("/tmp/project-a", name: "Custom")
        store.setName("/tmp/project-a", name: "   ")
        XCTAssertNil(store.projects[0].customName)
    }

    func testSetNameNilResetsToFolder() {
        store.addProject(path: "/tmp/project-a")
        store.setName("/tmp/project-a", name: "Custom")
        store.setName("/tmp/project-a", name: nil)
        XCTAssertNil(store.projects[0].customName)
        XCTAssertEqual(store.projects[0].name, "project-a")
    }

    func testSetNameEqualToFolderStoresNil() {
        store.addProject(path: "/tmp/project-a")
        store.setName("/tmp/project-a", name: "project-a")
        XCTAssertNil(store.projects[0].customName)
    }

    func testSetNameForUnknownPathIsNoOp() {
        store.addProject(path: "/tmp/project-a")
        store.setName("/tmp/nonexistent", name: "Something")
        XCTAssertNil(store.projects[0].customName)
    }

    func testCustomNamePersists() {
        store.addProject(path: "/tmp/project-a")
        store.setName("/tmp/project-a", name: "Persisted Name")

        let reloaded = ProjectStore(filePath: tempFile.path)
        XCTAssertEqual(reloaded.projects[0].customName, "Persisted Name")
        XCTAssertEqual(reloaded.projects[0].name, "Persisted Name")
    }

    func testReplaceProjectsPreservesCustomName() {
        store.addProject(path: "/tmp/project-a")
        store.setName("/tmp/project-a", name: "Alpha")
        store.addProject(path: "/tmp/project-b")

        let reordered = [
            Project(path: "/tmp/project-b"),
            Project(path: "/tmp/project-a"),
        ]
        store.replaceProjects(reordered)

        XCTAssertEqual(store.projects[1].customName, "Alpha")
        XCTAssertEqual(store.projects[1].name, "Alpha")
    }

    func testLegacyEntryWithoutNameDecodes() throws {
        let json = """
        [{"path": "/tmp/project-a", "binary": "claude"}]
        """
        try json.data(using: .utf8)!.write(to: tempFile)

        let migrated = ProjectStore(filePath: tempFile.path)
        XCTAssertEqual(migrated.projects.count, 1)
        XCTAssertEqual(migrated.projects[0].path, "/tmp/project-a")
        XCTAssertNil(migrated.projects[0].customName)
        XCTAssertEqual(migrated.projects[0].name, "project-a")
    }
}
