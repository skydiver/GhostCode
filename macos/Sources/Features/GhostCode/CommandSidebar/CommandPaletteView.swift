import SwiftUI

/// The right sidebar view showing configurable command buttons.
struct GhostCodeCommandPaletteView: View {
    @ObservedObject var store: CommandStore
    @ObservedObject var state: CommandPaletteState
    let onItemAction: (CommandItem.Action) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(store.sections) { section in
                        CommandSectionView(
                            section: section,
                            onItemAction: onItemAction
                        )
                    }
                }
                .padding(12)
            }

            Divider()

            Button(action: { store.openInEditor() }) {
                HStack(spacing: 8) {
                    Image(systemName: "gear")
                    Text("Edit Commands")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .frame(minWidth: 160, maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
        }
        .opacity(state.isLocked ? 0.4 : 1.0)
        .allowsHitTesting(!state.isLocked)
        .disabled(state.isLocked)
    }
}

/// A single section of command buttons.
struct CommandSectionView: View {
    let section: CommandSection
    let onItemAction: (CommandItem.Action) -> Void

    @State private var isCollapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCollapsed.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .frame(width: 12)

                    Text(section.name.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .kerning(0.5)

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                Group {
                    switch section.resolvedLayout {
                    case .flow:
                        FlowLayout(spacing: 6) {
                            ForEach(section.items) { item in
                                CommandButton(item: item) {
                                    if let action = item.action { onItemAction(action) }
                                }
                            }
                        }
                    case .list:
                        VStack(spacing: 6) {
                            ForEach(section.items) { item in
                                CommandButton(item: item, fullWidth: true) {
                                    if let action = item.action { onItemAction(action) }
                                }
                            }
                        }
                    case .tiles:
                        let columns = [
                            GridItem(.flexible(), spacing: 6),
                            GridItem(.flexible(), spacing: 6)
                        ]
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(section.items) { item in
                                CommandTile(item: item) {
                                    if let action = item.action { onItemAction(action) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .background(Color.primary.opacity(0.04))
        .clipShape(.rect(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipped()
    }
}

/// A single command button.
struct CommandButton: View {
    let item: CommandItem
    var fullWidth: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = item.icon {
                    CommandIcon(name: icon, size: 12)
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(.system(size: 13, weight: .medium,
                               design: item.label.hasPrefix("/") ? .monospaced : .default))
                        .foregroundStyle(.primary)

                    if let text = item.text, !item.label.hasPrefix("/"), text != item.label {
                        Text(text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(isHovered ? 0.06 : 0))
            .clipShape(.rect(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(isHovered ? 0.25 : 0.1), lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .instantTooltip(item.tooltip)
    }
}

/// A single app-launcher tile. Fixed height, name centered, used in `tiles` layout.
struct CommandTile: View {
    let item: CommandItem
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if let icon = item.icon {
                    CommandIcon(name: icon, size: 18)
                        .foregroundStyle(.primary)
                }
                Text(item.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 8)
            .background(Color.primary.opacity(isHovered ? 0.06 : 0))
            .clipShape(.rect(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(isHovered ? 0.25 : 0.1), lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .frame(height: 56)
        .onHover { hovering in
            isHovered = hovering
        }
        .instantTooltip(item.tooltip ?? item.executable)
    }
}

/// A simple horizontal flow layout that wraps items to the next line.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, (position, width)) in zip(result.positions, result.widths).enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(width: width, height: nil)
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews)
        -> (size: CGSize, positions: [CGPoint], widths: [CGFloat])
    {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var widths: [CGFloat] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let clampedWidth = min(size.width, maxWidth)

            if currentX + clampedWidth > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            let availableWidth = maxWidth - currentX
            let finalWidth = min(size.width, availableWidth)

            positions.append(CGPoint(x: currentX, y: currentY))
            widths.append(finalWidth)
            currentX += finalWidth + spacing
            let placedHeight = subview.sizeThatFits(
                ProposedViewSize(width: finalWidth, height: nil)
            ).height
            lineHeight = max(lineHeight, placedHeight)
            totalHeight = currentY + lineHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions, widths)
    }
}
