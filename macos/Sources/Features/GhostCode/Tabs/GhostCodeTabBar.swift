import SwiftUI

struct GhostCodeTabBar: View {
    @ObservedObject var tabGroup: ProjectTabGroup
    var onNewTab: () -> Void
    var onCloseTab: (Int) -> Void
    var onSelectTab: (Int) -> Void
    var onCloseOtherTabs: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabGroup.tabs.enumerated()), id: \.element.id) { index, tab in
                TabBarItem(
                    tab: tab,
                    isActive: index == tabGroup.activeTabIndex,
                    onSelect: { onSelectTab(index) },
                    onClose: { onCloseTab(index) },
                    onCloseOthers: { onCloseOtherTabs(index) }
                )
                if index < tabGroup.tabs.count - 1 {
                    Divider()
                        .frame(height: 14)
                        .opacity(0.3)
                }
            }

            Spacer()

            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
        }
        .frame(height: 30)
        .background(Color(nsColor: NSColor(white: 0.1, alpha: 1)))
    }
}

private struct TabBarItem: View {
    let tab: TabItem
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onCloseOthers: () -> Void

    @State private var isHovering = false
    @State private var isCloseHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tab.kind == .ai ? Color.blue : Color.green)
                .frame(width: 7, height: 7)

            Text(tab.title)
                .font(.system(size: 12))
                .foregroundColor(isActive ? .primary : .secondary)
                .lineLimit(1)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(isHovering || isActive ? .secondary : .clear)
                    .frame(width: 16, height: 16)
                    .background(
                        isCloseHovering
                            ? Color(nsColor: NSColor(white: 0.25, alpha: 1))
                            : Color.clear
                    )
                    .cornerRadius(3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isCloseHovering = $0 }
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(
            isActive
                ? Color(nsColor: NSColor(white: 0.17, alpha: 1))
                : Color.clear
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Close Tab") { onClose() }
            Button("Close Other Tabs") { onCloseOthers() }
        }
    }
}
