import Foundation
import Combine
import GhosttyKit

/// Manages the ordered set of terminal tabs for a single project.
final class ProjectTabGroup: ObservableObject {
    @Published var tabs: [TabItem] = []
    @Published var activeTabIndex: Int = 0

    var activeTab: TabItem? {
        guard activeTabIndex >= 0, activeTabIndex < tabs.count else { return nil }
        return tabs[activeTabIndex]
    }

    var isEmpty: Bool { tabs.isEmpty }

    func addTab(_ tab: TabItem) {
        tabs.append(tab)
        activeTabIndex = tabs.count - 1
    }

    @discardableResult
    func removeTab(at index: Int) -> TabItem? {
        guard index >= 0, index < tabs.count else { return nil }
        let removed = tabs.remove(at: index)
        if tabs.isEmpty {
            activeTabIndex = 0
        } else if index <= activeTabIndex {
            activeTabIndex = max(activeTabIndex - 1, 0)
        }
        return removed
    }

    @discardableResult
    func removeTab(withId id: UUID) -> TabItem? {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        return removeTab(at: index)
    }

    func activateTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        activeTabIndex = index
    }

    func moveTab(fromIndex: Int, toIndex: Int) {
        guard fromIndex != toIndex,
              fromIndex >= 0, fromIndex < tabs.count,
              toIndex >= 0, toIndex < tabs.count else { return }
        let tab = tabs.remove(at: fromIndex)
        tabs.insert(tab, at: toIndex)
        if activeTabIndex == fromIndex {
            activeTabIndex = toIndex
        } else if fromIndex < activeTabIndex, toIndex >= activeTabIndex {
            activeTabIndex -= 1
        } else if fromIndex > activeTabIndex, toIndex <= activeTabIndex {
            activeTabIndex += 1
        }
    }

    func moveTab(from sourceIndex: Int, by offset: Int) {
        let targetIndex = min(max(sourceIndex + offset, 0), tabs.count - 1)
        guard sourceIndex != targetIndex,
              sourceIndex >= 0, sourceIndex < tabs.count else { return }
        let tab = tabs.remove(at: sourceIndex)
        tabs.insert(tab, at: targetIndex)
        if activeTabIndex == sourceIndex {
            activeTabIndex = targetIndex
        } else if sourceIndex < activeTabIndex, targetIndex >= activeTabIndex {
            activeTabIndex -= 1
        } else if sourceIndex > activeTabIndex, targetIndex <= activeTabIndex {
            activeTabIndex += 1
        }
    }

    /// Navigate tabs using Ghostty's goto_tab semantics.
    /// Positive values are 1-indexed absolute positions.
    /// Negative sentinel values: PREVIOUS, NEXT, LAST.
    func gotoTab(_ tabIndex: Int32) {
        guard !tabs.isEmpty else { return }

        let finalIndex: Int
        if tabIndex <= 0 {
            if tabIndex == GHOSTTY_GOTO_TAB_PREVIOUS.rawValue {
                finalIndex = activeTabIndex == 0 ? tabs.count - 1 : activeTabIndex - 1
            } else if tabIndex == GHOSTTY_GOTO_TAB_NEXT.rawValue {
                finalIndex = activeTabIndex == tabs.count - 1 ? 0 : activeTabIndex + 1
            } else if tabIndex == GHOSTTY_GOTO_TAB_LAST.rawValue {
                finalIndex = tabs.count - 1
            } else {
                return
            }
        } else {
            finalIndex = min(Int(tabIndex - 1), tabs.count - 1)
        }

        guard finalIndex >= 0 else { return }
        activeTabIndex = finalIndex
    }
}
