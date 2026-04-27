import XCTest
@testable import Ghostty

final class ProjectStoreAttentionTests: XCTestCase {

    private func makeStore(with projects: [Project]) -> ProjectStore {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("attn-store-\(UUID().uuidString).json").path
        let store = ProjectStore(filePath: tempPath)
        store.replaceProjects(projects)
        return store
    }

    func test_setAttention_flipsHasAttentionForMatchingPath() {
        let store = makeStore(with: [Project(path: "/p/A"), Project(path: "/p/B")])

        store.setAttention("/p/A", hasAttention: true)
        XCTAssertTrue(store.projects.first { $0.path == "/p/A" }!.hasAttention)
        XCTAssertFalse(store.projects.first { $0.path == "/p/B" }!.hasAttention)

        store.setAttention("/p/A", hasAttention: false)
        XCTAssertFalse(store.projects.first { $0.path == "/p/A" }!.hasAttention)
    }

    func test_setAttention_unknownPath_isNoOp() {
        let store = makeStore(with: [Project(path: "/p/A")])
        store.setAttention("/p/missing", hasAttention: true)
        XCTAssertFalse(store.projects.first!.hasAttention)
    }

    func test_replaceProjects_preservesHasAttention_byPath() {
        let store = makeStore(with: [Project(path: "/p/A"), Project(path: "/p/B")])
        store.setAttention("/p/A", hasAttention: true)

        // Reorder + drop B; A is reordered but its attention should survive.
        store.replaceProjects([Project(path: "/p/A")])

        XCTAssertEqual(store.projects.count, 1)
        XCTAssertTrue(store.projects[0].hasAttention)
    }

    func test_setAttention_doesNotWriteToDisk() {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("attn-disk-\(UUID().uuidString).json").path
        let store = ProjectStore(filePath: tempPath)
        store.addProject(path: "/p/A")  // writes to disk
        let beforeMtime = try? FileManager.default.attributesOfItem(atPath: tempPath)[.modificationDate] as? Date

        // Sleep just long enough to make a mtime difference observable.
        Thread.sleep(forTimeInterval: 0.05)

        store.setAttention("/p/A", hasAttention: true)
        let afterMtime = try? FileManager.default.attributesOfItem(atPath: tempPath)[.modificationDate] as? Date

        XCTAssertEqual(beforeMtime, afterMtime, "setAttention must not save to disk")
    }
}
