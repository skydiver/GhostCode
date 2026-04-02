import AppKit
import SwiftUI
import GhosttyKit
import Combine

/// Shared state between ClaudeTTYController and CommandPaletteView.
final class CommandPaletteState: ObservableObject {
    @Published var isLocked: Bool = true
}

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
    let commandPaletteState = CommandPaletteState()

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

    // Keyboard event monitor for sidebar toggles
    private var eventMonitor: Any?

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

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
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
                state: commandPaletteState,
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

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.modifierFlags.contains([.command, .shift]) else {
                return event
            }
            switch event.charactersIgnoringModifiers {
            case "l", "L":
                self.toggleLeftSidebar(nil)
                return nil
            case "r", "R":
                self.toggleRightSidebar(nil)
                return nil
            default:
                return event
            }
        }
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

        // Set focused surface manually since windowDidLoad won't run
        // (we embed TerminalView directly, bypassing the nib-based window).
        if case .leaf(let view) = controller.surfaceTree.root {
            controller.focusedSurface = view
        }

        terminalControllers[project.path] = controller

        projectStore.setActive(project.path, active: true)
        switchToTerminal(controller, project: project)
        observeTerminalExit(controller, projectPath: project.path)
    }

    private func switchToTerminal(_ controller: TerminalController, project: Project) {
        centerContainer.subviews.forEach { $0.removeFromSuperview() }
        startupHostingView = nil

        // Create a TerminalView using the controller as both view model and delegate.
        // TerminalController conforms to TerminalViewModel and TerminalViewDelegate
        // (inherited from BaseTerminalController).
        let terminalView = TerminalView(
            ghostty: ghostty,
            viewModel: controller,
            delegate: controller
        )
        let hostingView = NSHostingView(rootView: terminalView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        centerContainer.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: centerContainer.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: centerContainer.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: centerContainer.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: centerContainer.trailingAnchor),
        ])

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
        guard let surfaceView = activeTerminalController?.focusedSurface,
              let surface = surfaceView.surface else { return }
        let fullText = text + "\r"
        let len = fullText.utf8CString.count
        guard len > 0 else { return }
        fullText.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(len - 1))
        }
    }

    // MARK: - Sidebar Toggles

    /// Toggle the left sidebar visibility.
    @IBAction func toggleLeftSidebar(_ sender: Any?) {
        leftSidebarItem.animator().isCollapsed.toggle()
    }

    /// Toggle the right sidebar visibility.
    @IBAction func toggleRightSidebar(_ sender: Any?) {
        rightSidebarItem.animator().isCollapsed.toggle()
    }

    // MARK: - Right Sidebar Lock

    private func updateRightSidebarLock() {
        commandPaletteState.isLocked = !hasActiveTerminal
    }

    // MARK: - Window Delegate

    func windowDidBecomeKey(_ notification: Notification) {
        refreshAllGitStatus()
    }

    private func refreshAllGitStatus() {
        for project in projectStore.projects {
            Task {
                if let status = await GitStatusProvider.fetchStatus(for: project.path) {
                    await MainActor.run {
                        projectStore.updateGitStatus(path: project.path, status: status)
                    }
                }
            }
        }
    }
}
