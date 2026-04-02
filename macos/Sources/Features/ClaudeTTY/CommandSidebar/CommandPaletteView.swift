import SwiftUI

/// The right sidebar view showing configurable command buttons.
struct ClaudeTTYCommandPaletteView: View {
    @ObservedObject var store: CommandStore
    @ObservedObject var state: CommandPaletteState
    let onSendCommand: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(store.sections) { section in
                        CommandSectionView(
                            section: section,
                            onSendCommand: onSendCommand
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
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .frame(minWidth: 160)
        .opacity(state.isLocked ? 0.4 : 1.0)
        .allowsHitTesting(!state.isLocked)
    }
}

/// A single section of command buttons.
struct CommandSectionView: View {
    let section: CommandSection
    let onSendCommand: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.name.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .kerning(0.5)

            FlowLayout(spacing: 6) {
                ForEach(section.items) { item in
                    CommandButton(item: item) {
                        onSendCommand(item.text)
                    }
                }
            }
        }
    }
}

/// A single command button.
struct CommandButton: View {
    let item: CommandItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(.system(size: 13, weight: .medium,
                           design: item.label.hasPrefix("/") ? .monospaced : .default))
                    .foregroundColor(.primary)

                if !item.label.hasPrefix("/") && item.text != item.label {
                    Text(item.text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalHeight = currentY + lineHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}
