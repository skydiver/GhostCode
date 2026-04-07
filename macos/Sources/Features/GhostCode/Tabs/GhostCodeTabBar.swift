import SwiftUI

struct GhostCodeTabBar: View {
    @ObservedObject var tabGroup: ProjectTabGroup
    var onNewShellTab: () -> Void
    var onNewAITab: () -> Void
    var onCloseTab: (Int) -> Void
    var onSelectTab: (Int) -> Void
    var onCloseOtherTabs: (Int) -> Void

    @State private var draggingTabId: UUID?
    @State private var tabMidpoints: [UUID: CGFloat] = [:]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabGroup.tabs.enumerated()), id: \.element.id) { index, tab in
                TabBarItem(
                    tab: tab,
                    isActive: index == tabGroup.activeTabIndex,
                    isDragging: draggingTabId == tab.id,
                    onSelect: { onSelectTab(index) },
                    onClose: { onCloseTab(index) },
                    onCloseOthers: { onCloseOtherTabs(index) }
                )
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: TabMidpointKey.self,
                            value: [tab.id: geo.frame(in: .named("tabbar")).midX]
                        )
                    }
                )
                if index < tabGroup.tabs.count - 1 {
                    Divider()
                        .frame(height: 14)
                        .opacity(0.3)
                }
            }

            Spacer()

            TabBarButton(icon: "sparkles", size: 10, tooltip: "New AI tab", action: onNewAITab)
            TabBarButton(icon: "plus", size: 11, tooltip: "New shell tab", action: onNewShellTab)
                .padding(.trailing, 6)
        }
        .frame(height: 30)
        .background(Color(nsColor: NSColor(white: 0.1, alpha: 1)))
        .coordinateSpace(name: "tabbar")
        .onPreferenceChange(TabMidpointKey.self) { tabMidpoints = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named("tabbar"))
                .onChanged { value in
                    // On first movement, determine which tab is being dragged
                    if draggingTabId == nil {
                        draggingTabId = tabAt(x: value.startLocation.x)
                    }
                    guard let dragId = draggingTabId,
                          let srcIdx = tabGroup.tabs.firstIndex(where: { $0.id == dragId }) else { return }

                    // Determine target index from cursor position
                    let targetIdx = indexAt(x: value.location.x)
                    if srcIdx != targetIdx {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            tabGroup.moveTab(fromIndex: srcIdx, toIndex: targetIdx)
                        }
                    }
                }
                .onEnded { _ in
                    draggingTabId = nil
                }
        )
    }

    /// Find the tab ID at a given X position in tab bar space.
    private func tabAt(x: CGFloat) -> UUID? {
        // Find the tab whose midpoint is closest to x
        var bestId: UUID?
        var bestDist: CGFloat = .infinity
        for (id, midX) in tabMidpoints {
            let dist = abs(midX - x)
            if dist < bestDist {
                bestDist = dist
                bestId = id
            }
        }
        return bestId
    }

    /// Determine the target index for a tab dragged to position x.
    private func indexAt(x: CGFloat) -> Int {
        // Count how many tab midpoints the cursor has passed
        let orderedMidpoints = tabGroup.tabs.compactMap { tab in
            tabMidpoints[tab.id]
        }
        var targetIdx = 0
        for midX in orderedMidpoints {
            if x > midX { targetIdx += 1 }
        }
        return min(max(targetIdx, 0), tabGroup.tabs.count - 1)
    }
}

private struct TabMidpointKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct TabBarItem: View {
    let tab: TabItem
    let isActive: Bool
    let isDragging: Bool
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
            isDragging
                ? Color(nsColor: NSColor(white: 0.22, alpha: 1))
                : isActive
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

private struct TabBarButton: View {
    let icon: String
    let size: CGFloat
    let tooltip: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(isHovering ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    isHovering
                        ? Color(nsColor: NSColor(white: 0.2, alpha: 1))
                        : Color.clear
                )
                .cornerRadius(5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .instantTooltip(tooltip)
    }
}
