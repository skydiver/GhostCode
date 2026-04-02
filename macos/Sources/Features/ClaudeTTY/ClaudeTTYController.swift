import AppKit
import SwiftUI
import GhosttyKit
import Combine

/// The main ClaudeTTY window controller. Manages a three-panel layout:
/// left sidebar (projects), center (terminal or startup), right sidebar (commands).
final class ClaudeTTYController: NSWindowController, NSWindowDelegate {
    let ghostty: Ghostty.App

    private let splitViewController = NSSplitViewController()

    // Sidebar hosting controllers
    private var leftSidebarItem: NSSplitViewItem!
    private var centerItem: NSSplitViewItem!
    private var rightSidebarItem: NSSplitViewItem!

    // Stores
    let projectStore = ProjectStore()
    let commandStore = CommandStore()

    // The currently visible terminal controller, if any
    private(set) var activeTerminalController: TerminalController?

    // Maps project paths to their active terminal controllers
    private var terminalControllers: [String: TerminalController] = [:]

    // Center content: either startup view or terminal
    private let centerContainer = NSView()

    // The startup view, shown when no terminal is active
    private var startupHostingView: NSView?

    // Combine cancellables for terminal exit observation
    private var exitCancellables: [String: AnyCancellable] = [:]

    init(_ ghostty: Ghostty.App) {
        self.ghostty = ghostty

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ClaudeTTY"
        window.setFrameAutosaveName("ClaudeTTYMainWindow")
        window.minSize = NSSize(width: 600, height: 400)

        super.init(window: window)
        window.delegate = self

        setupSplitView()
        showStartupScreen()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupSplitView() {
        // Left sidebar: project list
        let leftView = NSHostingController(
            rootView: ProjectListView(
                store: projectStore,
                onSelectProject: { [weak self] project in
                    self?.activateProject(project)
                }
            )
        )
        leftSidebarItem = NSSplitViewItem(sidebarWithViewController: leftView)
        leftSidebarItem.minimumThickness = 180
        leftSidebarItem.maximumThickness = 300
        leftSidebarItem.canCollapse = true

        // Center: terminal or startup screen
        let centerVC = NSViewController()
        centerVC.view = centerContainer
        centerItem = NSSplitViewItem(viewController: centerVC)
        centerItem.minimumThickness = 400

        // Right sidebar: command palette
        let rightView = NSHostingController(
            rootView: CommandPaletteView(
                store: commandStore,
                isLocked: !hasActiveTerminal,
                onSendCommand: { [weak self] text in
                    self?.sendTextToActiveTerminal(text)
                }
            )
        )
        rightSidebarItem = NSSplitViewItem(viewController: rightView)
        rightSidebarItem.minimumThickness = 160
        rightSidebarItem.maximumThickness = 280
        rightSidebarItem.canCollapse = true

        splitViewController.addSplitViewItem(leftSidebarItem)
        splitViewController.addSplitViewItem(centerItem)
        splitViewController.addSplitViewItem(rightSidebarItem)

        window?.contentViewController = splitViewController
    }

    var hasActiveTerminal: Bool {
        activeTerminalController != nil
    }

    // MARK: - Startup Screen

    func showStartupScreen() {
        centerContainer.subviews.forEach { $0.removeFromSuperview() }

        let hostingView = NSHostingView(rootView: StartupView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        centerContainer.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: centerContainer.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: centerContainer.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: centerContainer.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: centerContainer.trailingAnchor),
        ])
        startupHostingView = hostingView
        activeTerminalController = nil
        updateRightSidebarLock()
    }

    // MARK: - Project Activation

    func activateProject(_ project: Project) {
        if let existingController = terminalControllers[project.path] {
            switchToTerminal(existingController, project: project)
            return
        }
        spawnTerminal(for: project)
    }

    private func spawnTerminal(for project: Project) {
        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = project.path
        config.command = "claude"

        let controller = TerminalController(ghostty, withBaseConfig: config)
        terminalControllers[project.path] = controller

        projectStore.setActive(project.path, active: true)
        switchToTerminal(controller, project: project)
        observeTerminalExit(controller, projectPath: project.path)
    }

    private func switchToTerminal(_ controller: TerminalController, project: Project) {
        centerContainer.subviews.forEach { $0.removeFromSuperview() }
        startupHostingView = nil

        // Embed the terminal's view in the center container.
        // TerminalController uses nib-based windows, so we access its content view.
        // This will be refined in Task 11 when we validate the actual integration.
        if let terminalView = controller.window?.contentView {
            terminalView.removeFromSuperview()
            terminalView.translatesAutoresizingMaskIntoConstraints = false
            centerContainer.addSubview(terminalView)
            NSLayoutConstraint.activate([
                terminalView.topAnchor.constraint(equalTo: centerContainer.topAnchor),
                terminalView.bottomAnchor.constraint(equalTo: centerContainer.bottomAnchor),
                terminalView.leadingAnchor.constraint(equalTo: centerContainer.leadingAnchor),
                terminalView.trailingAnchor.constraint(equalTo: centerContainer.trailingAnchor),
            ])
        }

        activeTerminalController = controller
        projectStore.setVisible(project.path)
        updateRightSidebarLock()
    }

    private func observeTerminalExit(_ controller: TerminalController, projectPath: String) {
        let cancellable = controller.$surfaceTree
            .dropFirst()
            .filter(\.isEmpty)
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleTerminalExit(projectPath: projectPath)
            }
        exitCancellables[projectPath] = cancellable
    }

    private func handleTerminalExit(projectPath: String) {
        exitCancellables.removeValue(forKey: projectPath)
        terminalControllers.removeValue(forKey: projectPath)
        projectStore.setActive(projectPath, active: false)

        if let nextPath = terminalControllers.keys.first,
           let nextController = terminalControllers[nextPath],
           let project = projectStore.project(forPath: nextPath) {
            switchToTerminal(nextController, project: project)
        } else {
            showStartupScreen()
        }
    }

    // MARK: - Command Execution

    func sendTextToActiveTerminal(_ text: String) {
        guard let surfaceView = activeTerminalController?.focusedSurface else { return }
        let fullText = text + "\r"
        for c in fullText.utf8 {
            let byte = UInt8(c)
            withUnsafePointer(to: byte) { ptr in
                // This will be refined in Task 11 when we wire
                // the actual ghostty surface input method.
                _ = ptr // suppress unused warning
                _ = surfaceView // suppress unused warning
            }
        }
    }

    // MARK: - Right Sidebar Lock

    private func updateRightSidebarLock() {
        // Will be implemented in Task 12 with reactive state
    }
}
