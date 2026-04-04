import SwiftUI
import AppKit

// MARK: - View Modifier

extension View {
    /// Shows a floating tooltip to the left of the view on hover.
    func instantTooltip(_ text: String?) -> some View {
        background(text.map { TooltipTracker(text: $0) })
    }
}

// MARK: - NSPanel Tooltip

/// Manages a single floating tooltip panel. Singleton ensures only one tooltip is visible at a time.
final class TooltipPanel {
    static let shared = TooltipPanel()
    private var panel: NSPanel?

    func show(text: String, anchorView: NSView) {
        dismiss()

        guard let parentWindow = anchorView.window else { return }

        let maxWidth: CGFloat = 250

        let padding: CGFloat = 12

        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.usesSingleLineMode = false
        label.cell?.wraps = true
        label.cell?.lineBreakMode = .byWordWrapping
        label.preferredMaxLayoutWidth = maxWidth

        // Size to fit unconstrained to get natural width
        label.sizeToFit()
        let labelWidth = min(label.frame.width, maxWidth)

        // Re-measure height at the constrained width
        let cellHeight = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: labelWidth, height: .greatestFiniteMagnitude)).height ?? label.frame.height
        label.frame = NSRect(x: padding, y: padding, width: labelWidth, height: cellHeight)

        let contentSize = NSSize(
            width: labelWidth + padding * 2,
            height: cellHeight + padding * 2
        )

        let viewFrame = parentWindow.convertToScreen(
            anchorView.convert(anchorView.bounds, to: nil)
        )

        // Position to the left of the anchor, vertically centered.
        // If it would go off-screen, flip to the right.
        var x = viewFrame.minX - contentSize.width - 6
        if x < (anchorView.window?.screen?.visibleFrame.minX ?? 0) {
            x = viewFrame.maxX + 6
        }
        let y = viewFrame.midY - contentSize.height / 2

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: contentSize.width, height: contentSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.ignoresMouseEvents = true

        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: contentSize))
        effectView.material = .toolTip
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 8
        effectView.layer?.masksToBounds = true

        effectView.addSubview(label)

        panel.contentView = effectView
        panel.orderFront(nil)
        self.panel = panel
    }

    func dismiss() {
        panel?.close()
        panel = nil
    }
}

// MARK: - Tracking View

/// An invisible NSView that tracks mouse hover and triggers the tooltip panel.
private struct TooltipTracker: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> TooltipTrackingView {
        let view = TooltipTrackingView()
        view.text = text
        return view
    }

    func updateNSView(_ nsView: TooltipTrackingView, context: Context) {
        nsView.text = text
    }
}

final class TooltipTrackingView: NSView {
    var text: String = ""
    private var area: NSTrackingArea?
    private var hoverTask: DispatchWorkItem?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let newArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self
        )
        addTrackingArea(newArea)
        area = newArea
    }

    override func mouseEntered(with event: NSEvent) {
        hoverTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            TooltipPanel.shared.show(text: text, anchorView: self)
        }
        hoverTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: task)
    }

    override func mouseExited(with event: NSEvent) {
        hoverTask?.cancel()
        TooltipPanel.shared.dismiss()
    }
}
