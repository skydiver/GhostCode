import AppKit
import SwiftUI
import GhosttyKit
import Combine

/// Shared state between ClaudeTTYController and ClaudeTTYCommandPaletteView.
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

    // Combine cancellables for terminal exit polling
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
        window.minSize = NSSize(width: 600, height: 400)

        super.init(window: window)
        window.delegate = self

        setupSplitView()
        showStartupScreen()

        // Restore saved frame after all subviews are set up, so the split
        // view layout doesn't override the restored geometry.
        window.setFrameAutosaveName("ClaudeTTYMainWindow")
        if !window.setFrameUsingName("ClaudeTTYMainWindow") {
            window.center()
        }
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
        leftView.sizingOptions = []
        leftSidebarItem = NSSplitViewItem(viewController: leftView)
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
            rootView: ClaudeTTYCommandPaletteView(
                store: commandStore,
                state: commandPaletteState,
                onSendCommand: { [weak self] text in
                    self?.sendTextToActiveTerminal(text)
                }
            )
        )
        rightView.sizingOptions = []
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
        projectStore.setSelected(nil)
        updateRightSidebarLock()
    }

    // MARK: - Project Landing

    private func showProjectLanding(for project: Project) {
        centerContainer.subviews.forEach { $0.removeFromSuperview() }

        let landingView = ProjectLandingView(
            projectName: project.name,
            onStartSession: { [weak self] in
                self?.spawnTerminal(for: project)
            },
            onResumeSession: { [weak self] in
                self?.spawnTerminal(for: project, resume: true)
            }
        )
        let hostingView = NSHostingView(rootView: landingView)
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
        projectStore.setSelected(project.path)
        updateRightSidebarLock()
    }

    // MARK: - Project Activation

    func activateProject(_ project: Project) {
        if let existingController = terminalControllers[project.path] {
            // If the process has exited, clean up and show landing page
            if existingController.surfaceTree.isEmpty || isProcessExited(existingController) {
                terminalControllers.removeValue(forKey: project.path)
                exitCancellables.removeValue(forKey: project.path)
                projectStore.setActive(project.path, active: false)
                showProjectLanding(for: project)
                return
            }
            switchToTerminal(existingController, project: project)
            return
        }
        showProjectLanding(for: project)
    }

    private func spawnTerminal(for project: Project, resume: Bool = false) {
        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = project.path
        // TODO: restore to ClaudeTTYConfig.resolveCommand("claude") / "claude --continue"
        config.command = resume ? "/usr/bin/nano" : "/usr/bin/nano"

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
        startupHostingView = nil
        activeTerminalController = controller
        projectStore.setVisible(project.path)
        updateRightSidebarLock()

        // Build the new terminal view before removing the old one to avoid a
        // visible flash. We defer the swap to the next run loop so the center
        // container has valid bounds from the previous layout pass.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let terminalView = TerminalView(
                ghostty: self.ghostty,
                viewModel: controller,
                delegate: controller
            )
            let hostingView = NSHostingView(rootView: terminalView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            hostingView.frame = self.centerContainer.bounds
            self.centerContainer.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: self.centerContainer.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: self.centerContainer.bottomAnchor),
                hostingView.leadingAnchor.constraint(equalTo: self.centerContainer.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: self.centerContainer.trailingAnchor),
            ])

            // Remove all previous subviews now that the new one is in place.
            for subview in self.centerContainer.subviews where subview !== hostingView {
                subview.removeFromSuperview()
            }
        }
    }

    private func observeTerminalExit(_ controller: TerminalController, projectPath: String) {
        let cancellable = Timer.publish(every: 0.3, on: .main, in: .common)
            .autoconnect()
            .first(where: { [weak self] _ in
                self?.isProcessExited(controller) ?? true
            })
            .sink { [weak self] _ in
                self?.handleTerminalExit(projectPath: projectPath)
            }
        exitCancellables[projectPath] = cancellable
    }

    private func handleTerminalExit(projectPath: String) {
        guard terminalControllers.removeValue(forKey: projectPath) != nil else { return }
        exitCancellables.removeValue(forKey: projectPath)
        projectStore.setActive(projectPath, active: false)
        projectStore.removeFromHistory(projectPath)

        if let previousPath = projectStore.previousActiveProjectPath(excluding: projectPath),
           let controller = terminalControllers[previousPath],
           let project = projectStore.project(forPath: previousPath) {
            switchToTerminal(controller, project: project)
        } else {
            showStartupScreen()
        }
    }

    private func isProcessExited(_ controller: TerminalController) -> Bool {
        guard case .leaf(let view) = controller.surfaceTree.root else { return true }
        return view.processExited
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
