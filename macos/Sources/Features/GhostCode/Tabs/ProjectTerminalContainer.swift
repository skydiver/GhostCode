import SwiftUI
import GhosttyKit

struct ProjectTerminalContainer: View {
    @ObservedObject var tabGroup: ProjectTabGroup
    let ghostty: Ghostty.App
    var onNewTab: () -> Void
    var onCloseTab: (Int) -> Void
    var onCloseOtherTabs: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            GhostCodeTabBar(
                tabGroup: tabGroup,
                onNewTab: onNewTab,
                onCloseTab: onCloseTab,
                onSelectTab: { index in
                    tabGroup.activateTab(at: index)
                },
                onCloseOtherTabs: onCloseOtherTabs
            )

            Divider()

            if let activeTab = tabGroup.activeTab {
                TerminalView(
                    ghostty: ghostty,
                    viewModel: activeTab.controller,
                    delegate: activeTab.controller
                )
                .id(activeTab.id)
                .environment(\.surfaceGrabHandleEnabled, false)
            }
        }
    }
}
