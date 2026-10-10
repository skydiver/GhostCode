import Foundation

/// Tracks whether the window is in "full canvas" mode (both sidebars hidden)
/// and remembers which sidebars were open so the layout can be restored.
final class FullCanvasState: ObservableObject {
    typealias SidebarLayout = (leftOpen: Bool, rightOpen: Bool)

    @Published private(set) var isActive = false
    private var savedLayout: SidebarLayout?

    /// Enter full canvas, remembering the current layout. No-op if already active.
    func enter(leftOpen: Bool, rightOpen: Bool) {
        guard !isActive else { return }
        savedLayout = (leftOpen, rightOpen)
        isActive = true
    }

    /// Leave full canvas and return the layout to restore, or nil if not active.
    func exit() -> SidebarLayout? {
        guard isActive else { return nil }
        let layout = savedLayout
        savedLayout = nil
        isActive = false
        return layout
    }

    /// Leave full canvas without restoring anything.
    func cancel() {
        guard isActive else { return }
        savedLayout = nil
        isActive = false
    }
}
