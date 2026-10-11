import XCTest
import AppKit
@testable import Ghostty

final class InstantTooltipTests: XCTestCase {
    func testTooltipClosesWhenAnchorLeavesWindow() {
        let window = makeWindow()
        let anchor = TooltipTrackingView(frame: NSRect(x: 10, y: 10, width: 50, height: 20))
        window.contentView?.addSubview(anchor)
        addTeardownBlock {
            TooltipPanel.shared.dismiss()
            window.close()
        }

        TooltipPanel.shared.show(text: "Hello", anchorView: anchor)
        XCTAssertTrue(TooltipPanel.shared.isShowing)

        anchor.removeFromSuperview()

        XCTAssertFalse(TooltipPanel.shared.isShowing)
    }

    func testRemovingOtherViewKeepsTooltip() {
        let window = makeWindow()
        let anchor = TooltipTrackingView(frame: NSRect(x: 10, y: 10, width: 50, height: 20))
        let other = TooltipTrackingView(frame: NSRect(x: 100, y: 10, width: 50, height: 20))
        window.contentView?.addSubview(anchor)
        window.contentView?.addSubview(other)
        addTeardownBlock {
            TooltipPanel.shared.dismiss()
            window.close()
        }

        TooltipPanel.shared.show(text: "Hello", anchorView: anchor)
        other.removeFromSuperview()

        XCTAssertTrue(TooltipPanel.shared.isShowing)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        // Owned by the test; the default would release it a second time on close.
        window.isReleasedWhenClosed = false
        return window
    }
}
