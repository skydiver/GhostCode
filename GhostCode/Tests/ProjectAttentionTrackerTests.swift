import XCTest
import Combine
@testable import Ghostty

final class ProjectAttentionTrackerTests: XCTestCase {

    /// Drains the main queue through two async hops. The wiring layer has two
    /// `.receive(on: DispatchQueue.main)` boundaries (upstream snapshot sink +
    /// per-tab bell sink), so a single-hop sentinel can fulfill before the
    /// second hop's work runs. Double-hopping ensures all triggered work is
    /// drained before assertions fire.
    private func drainMain() {
        let exp = expectation(description: "drain main")
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 0.5)
    }

    // MARK: - setBell core API

    func test_setBell_AI_true_addsProjectAndTab() {
        let tracker = ProjectAttentionTracker()
        let id = UUID()
        tracker.setBell(projectPath: "/p/A", tabId: id, hasBell: true)

        XCTAssertEqual(tracker.attentionProjects, ["/p/A"])
        XCTAssertEqual(tracker.attentionTabs, [id])
    }

    func test_setBell_falseAfterTrue_removesTab_andClearsProjectIfEmpty() {
        let tracker = ProjectAttentionTracker()
        let id = UUID()
        tracker.setBell(projectPath: "/p/A", tabId: id, hasBell: true)
        tracker.setBell(projectPath: "/p/A", tabId: id, hasBell: false)

        XCTAssertTrue(tracker.attentionProjects.isEmpty)
        XCTAssertTrue(tracker.attentionTabs.isEmpty)
    }

    func test_twoAITabs_inSameProject_clearingOneKeepsProject() {
        let tracker = ProjectAttentionTracker()
        let id1 = UUID(), id2 = UUID()
        tracker.setBell(projectPath: "/p/A", tabId: id1, hasBell: true)
        tracker.setBell(projectPath: "/p/A", tabId: id2, hasBell: true)

        XCTAssertEqual(tracker.attentionProjects, ["/p/A"])
        XCTAssertEqual(tracker.attentionTabs, [id1, id2])

        tracker.setBell(projectPath: "/p/A", tabId: id1, hasBell: false)

        XCTAssertEqual(tracker.attentionProjects, ["/p/A"])
        XCTAssertEqual(tracker.attentionTabs, [id2])
    }

    // MARK: - clearAttention

    func test_clearAttention_removesProjectAndItsTabs_butLeavesOtherProjects() {
        let tracker = ProjectAttentionTracker()
        let aTab = UUID(), bTab = UUID()
        tracker.setBell(projectPath: "/p/A", tabId: aTab, hasBell: true)
        tracker.setBell(projectPath: "/p/B", tabId: bTab, hasBell: true)

        tracker.clearAttention(projectPath: "/p/A")

        XCTAssertEqual(tracker.attentionProjects, ["/p/B"])
        XCTAssertEqual(tracker.attentionTabs, [bTab])
    }

    func test_clearAttention_unknownProject_isNoOp() {
        let tracker = ProjectAttentionTracker()
        tracker.clearAttention(projectPath: "/p/none")
        XCTAssertTrue(tracker.attentionProjects.isEmpty)
        XCTAssertTrue(tracker.attentionTabs.isEmpty)
    }

    // MARK: - reconcileTabs

    func test_reconcileTabs_prunesStaleUUIDs_andClearsProjectIfEmpty() {
        let tracker = ProjectAttentionTracker()
        let live = UUID(), stale = UUID()
        tracker.setBell(projectPath: "/p/A", tabId: live, hasBell: true)
        tracker.setBell(projectPath: "/p/A", tabId: stale, hasBell: true)

        tracker.reconcileTabs(projectPath: "/p/A", liveTabIds: [live])
        XCTAssertEqual(tracker.attentionTabs, [live])
        XCTAssertEqual(tracker.attentionProjects, ["/p/A"])

        tracker.reconcileTabs(projectPath: "/p/A", liveTabIds: [])
        XCTAssertTrue(tracker.attentionTabs.isEmpty)
        XCTAssertTrue(tracker.attentionProjects.isEmpty)
    }

    // MARK: - stopTracking

    func test_stopTracking_clearsState() {
        let tracker = ProjectAttentionTracker()
        let id = UUID()
        tracker.setBell(projectPath: "/p/A", tabId: id, hasBell: true)
        tracker.stopTracking(projectPath: "/p/A")

        XCTAssertTrue(tracker.attentionProjects.isEmpty)
        XCTAssertTrue(tracker.attentionTabs.isEmpty)
    }

    // MARK: - Wiring layer

    func test_wiring_aiBellTrue_propagatesToAttentionSets() {
        let tracker = ProjectAttentionTracker()
        let bell = CurrentValueSubject<Bool, Never>(false)
        let id = UUID()
        let tabs = CurrentValueSubject<[TrackedTab], Never>([
            TrackedTab(id: id, kind: .ai, bellPublisher: bell.eraseToAnyPublisher())
        ])
        tracker.startTracking(projectPath: "/p/A", trackedTabs: tabs.eraseToAnyPublisher())

        bell.send(true)
        drainMain()

        XCTAssertEqual(tracker.attentionProjects, ["/p/A"])
        XCTAssertEqual(tracker.attentionTabs, [id])
    }

    func test_wiring_shellTab_isIgnored() {
        let tracker = ProjectAttentionTracker()
        let bell = CurrentValueSubject<Bool, Never>(false)
        let id = UUID()
        let tabs = CurrentValueSubject<[TrackedTab], Never>([
            TrackedTab(id: id, kind: .shell, bellPublisher: bell.eraseToAnyPublisher())
        ])
        tracker.startTracking(projectPath: "/p/A", trackedTabs: tabs.eraseToAnyPublisher())

        bell.send(true)
        drainMain()

        XCTAssertTrue(tracker.attentionProjects.isEmpty)
        XCTAssertTrue(tracker.attentionTabs.isEmpty)
    }

    func test_wiring_tabRemoved_purgesUUID() {
        let tracker = ProjectAttentionTracker()
        let bell1 = CurrentValueSubject<Bool, Never>(false)
        let bell2 = CurrentValueSubject<Bool, Never>(false)
        let id1 = UUID(), id2 = UUID()
        let tabs = CurrentValueSubject<[TrackedTab], Never>([
            TrackedTab(id: id1, kind: .ai, bellPublisher: bell1.eraseToAnyPublisher()),
            TrackedTab(id: id2, kind: .ai, bellPublisher: bell2.eraseToAnyPublisher()),
        ])
        tracker.startTracking(projectPath: "/p/A", trackedTabs: tabs.eraseToAnyPublisher())

        bell1.send(true); bell2.send(true)
        drainMain()
        XCTAssertEqual(tracker.attentionTabs.count, 2)

        // Drop tab 1 from the snapshot — reconcileTabs must purge id1.
        tabs.send([
            TrackedTab(id: id2, kind: .ai, bellPublisher: bell2.eraseToAnyPublisher()),
        ])
        drainMain()

        XCTAssertEqual(tracker.attentionTabs, [id2])
        XCTAssertEqual(tracker.attentionProjects, ["/p/A"])
    }

    func test_wiring_startTracking_isIdempotent() {
        let tracker = ProjectAttentionTracker()
        let bell = CurrentValueSubject<Bool, Never>(false)
        let id = UUID()
        let tabs = CurrentValueSubject<[TrackedTab], Never>([
            TrackedTab(id: id, kind: .ai, bellPublisher: bell.eraseToAnyPublisher())
        ])
        tracker.startTracking(projectPath: "/p/A", trackedTabs: tabs.eraseToAnyPublisher())

        // Second call must be a no-op — passing a different (empty) publisher
        // should not replace the live subscription.
        let other = CurrentValueSubject<[TrackedTab], Never>([])
        tracker.startTracking(projectPath: "/p/A", trackedTabs: other.eraseToAnyPublisher())

        bell.send(true)
        drainMain()

        XCTAssertEqual(tracker.attentionTabs, [id], "second startTracking must be a no-op")
    }

    func test_wiring_stopTracking_clearsBothBags() {
        let tracker = ProjectAttentionTracker()
        let bell = CurrentValueSubject<Bool, Never>(false)
        let id = UUID()
        let tabs = CurrentValueSubject<[TrackedTab], Never>([
            TrackedTab(id: id, kind: .ai, bellPublisher: bell.eraseToAnyPublisher())
        ])
        tracker.startTracking(projectPath: "/p/A", trackedTabs: tabs.eraseToAnyPublisher())

        bell.send(true)
        drainMain()
        XCTAssertEqual(tracker.attentionTabs, [id])

        tracker.stopTracking(projectPath: "/p/A")
        XCTAssertTrue(tracker.attentionTabs.isEmpty)
        XCTAssertTrue(tracker.attentionProjects.isEmpty)

        // After stopTracking, further bell sends must be ignored.
        bell.send(false); bell.send(true)
        drainMain()
        XCTAssertTrue(tracker.attentionTabs.isEmpty, "subscriptions must be torn down")
    }
}
