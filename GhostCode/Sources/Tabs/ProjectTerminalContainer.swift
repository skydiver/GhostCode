import SwiftUI

struct ProjectTerminalContainer: View {
    @ObservedObject var tabGroup: ProjectTabGroup
    @ObservedObject var attentionTracker: ProjectAttentionTracker
    let ghostty: Ghostty.App
    var onNewShellTab: () -> Void
    var onNewAITab: () -> Void
    var onCloseTab: (Int) -> Void
    var onSelectTab: (Int) -> Void
    var onCloseOtherTabs: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            GhostCodeTabBar(
                tabGroup: tabGroup,
                attentionTabs: attentionTracker.attentionTabs,
                onNewShellTab: onNewShellTab,
                onNewAITab: onNewAITab,
                onCloseTab: onCloseTab,
                onSelectTab: onSelectTab,
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
