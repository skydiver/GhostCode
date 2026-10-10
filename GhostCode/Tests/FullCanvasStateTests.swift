import XCTest
import Combine
@testable import Ghostty

final class FullCanvasStateTests: XCTestCase {

    func test_startsInactive() {
        XCTAssertFalse(FullCanvasState().isActive)
    }

    func test_enterActivates() {
        let state = FullCanvasState()
        state.enter(leftOpen: true, rightOpen: true)
        XCTAssertTrue(state.isActive)
    }

    func test_exitReturnsStoredLayout_bothOpen() {
        let state = FullCanvasState()
        state.enter(leftOpen: true, rightOpen: true)
        let layout = state.exit()
        XCTAssertEqual(layout?.leftOpen, true)
        XCTAssertEqual(layout?.rightOpen, true)
        XCTAssertFalse(state.isActive)
    }

    func test_exitReturnsStoredLayout_leftOnly() {
        let state = FullCanvasState()
        state.enter(leftOpen: true, rightOpen: false)
        let layout = state.exit()
        XCTAssertEqual(layout?.leftOpen, true)
        XCTAssertEqual(layout?.rightOpen, false)
    }

    func test_exitReturnsStoredLayout_rightOnly() {
        let state = FullCanvasState()
        state.enter(leftOpen: false, rightOpen: true)
        let layout = state.exit()
        XCTAssertEqual(layout?.leftOpen, false)
        XCTAssertEqual(layout?.rightOpen, true)
    }

    func test_exitReturnsStoredLayout_noneOpen() {
        let state = FullCanvasState()
        state.enter(leftOpen: false, rightOpen: false)
        let layout = state.exit()
        XCTAssertNotNil(layout)
        XCTAssertEqual(layout?.leftOpen, false)
        XCTAssertEqual(layout?.rightOpen, false)
        XCTAssertFalse(state.isActive)
    }

    func test_exitWhenInactiveReturnsNil() {
        let state = FullCanvasState()
        XCTAssertNil(state.exit())
        XCTAssertFalse(state.isActive)
    }

    func test_enterTwiceKeepsFirstLayout() {
        let state = FullCanvasState()
        state.enter(leftOpen: true, rightOpen: false)
        state.enter(leftOpen: false, rightOpen: true)
        let layout = state.exit()
        XCTAssertEqual(layout?.leftOpen, true)
        XCTAssertEqual(layout?.rightOpen, false)
    }

    func test_cancelDeactivatesAndForgetsLayout() {
        let state = FullCanvasState()
        state.enter(leftOpen: true, rightOpen: true)
        state.cancel()
        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.exit())
    }

    func test_isActivePublishesChanges() {
        let state = FullCanvasState()
        var seen: [Bool] = []
        let cancellable = state.$isActive.sink { seen.append($0) }
        state.enter(leftOpen: true, rightOpen: true)
        _ = state.exit()
        cancellable.cancel()
        XCTAssertEqual(seen, [false, true, false])
    }
}
