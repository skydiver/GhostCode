import XCTest
import Combine
@testable import Ghostty

final class ProjectAttentionTrackerTests: XCTestCase {

    // MARK: - setBell core API

    func test_setBell_AI_true_addsProjectAndTab() {
        let tracker = ProjectAttentionTracker()
        let id = UUID()
        tracker.setBell(projectPath: "/p/A", tabId: id, isAI: true, hasBell: true)

        XCTAssertEqual(tracker.attentionProjects, ["/p/A"])
        XCTAssertEqual(tracker.attentionTabs, [id])
    }

    func test_setBell_shellTab_isIgnored() {
        let tracker = ProjectAttentionTracker()
        tracker.setBell(projectPath: "/p/A", tabId: UUID(), isAI: false, hasBell: true)

        XCTAssertTrue(tracker.attentionProjects.isEmpty)
        XCTAssertTrue(tracker.attentionTabs.isEmpty)
    }

    func test_setBell_falseAfterTrue_removesTab_andClearsProjectIfEmpty() {
        let tracker = ProjectAttentionTracker()
        let id = UUID()
        tracker.setBell(projectPath: "/p/A", tabId: id, isAI: true, hasBell: true)
        tracker.setBell(projectPath: "/p/A", tabId: id, isAI: true, hasBell: false)

        XCTAssertTrue(tracker.attentionProjects.isEmpty)
        XCTAssertTrue(tracker.attentionTabs.isEmpty)
    }

    func test_twoAITabs_inSameProject_clearingOneKeepsProject() {
        let tracker = ProjectAttentionTracker()
        let id1 = UUID(), id2 = UUID()
        tracker.setBell(projectPath: "/p/A", tabId: id1, isAI: true, hasBell: true)
        tracker.setBell(projectPath: "/p/A", tabId: id2, isAI: true, hasBell: true)

        XCTAssertEqual(tracker.attentionProjects, ["/p/A"])
        XCTAssertEqual(tracker.attentionTabs, [id1, id2])

        tracker.setBell(projectPath: "/p/A", tabId: id1, isAI: true, hasBell: false)

        XCTAssertEqual(tracker.attentionProjects, ["/p/A"])
        XCTAssertEqual(tracker.attentionTabs, [id2])
    }

    // MARK: - clearAttention

    func test_clearAttention_removesProjectAndItsTabs_butLeavesOtherProjects() {
        let tracker = ProjectAttentionTracker()
        let aTab = UUID(), bTab = UUID()
        tracker.setBell(projectPath: "/p/A", tabId: aTab, isAI: true, hasBell: true)
        tracker.setBell(projectPath: "/p/B", tabId: bTab, isAI: true, hasBell: true)

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
        tracker.setBell(projectPath: "/p/A", tabId: live, isAI: true, hasBell: true)
        tracker.setBell(projectPath: "/p/A", tabId: stale, isAI: true, hasBell: true)

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
        tracker.setBell(projectPath: "/p/A", tabId: id, isAI: true, hasBell: true)
        tracker.stopTracking(projectPath: "/p/A")

        XCTAssertTrue(tracker.attentionProjects.isEmpty)
        XCTAssertTrue(tracker.attentionTabs.isEmpty)
    }
}
