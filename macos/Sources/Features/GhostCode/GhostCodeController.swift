import AppKit
import SwiftUI
import GhosttyKit
import Combine

/// Shared state between GhostCodeController and GhostCodeCommandPaletteView.
final class CommandPaletteState: ObservableObject {
    @Published var isLocked: Bool = true
}

/// The main GhostCode window controller. Manages a three-panel layout:
/// left sidebar (projects), center (terminal or startup), right sidebar (commands).
final class GhostCodeController: NSWindowController, NSWindowDelegate {
    let ghostty: Ghostty.App

    private let splitViewController = NSSplitViewController()

    // Sidebar hosting controllers
    private var leftSidebarItem: NSSplitViewItem!
    private var rightSidebarItem: NSSplitViewItem!

    // Stores
    let projectStore = ProjectStore()
    let commandStore = CommandStore()
    let commandPaletteState = CommandPaletteState()
    let attentionTracker = ProjectAttentionTracker()
    let pulseClock = PulseClock()
    private var attentionBridgeCancellable: AnyCancellable?

    // The project path whose terminals are currently displayed in the center pane
    private var activeProjectPath: String?

    // Maps project paths to their tab groups
    private var projectTabs: [String: ProjectTabGroup] = [:]

    // Center content: either startup view or terminal
    private let centerContainer = NSView()

    // Combine cancellables for per-tab exit polling, keyed by TabItem.id
    private var exitCancellables: [UUID: AnyCancellable] = [:]

    // Coalesces rapid focus transfers (e.g. pressing Cmd+T quickly)
    private var pendingFocusWork: DispatchWorkItem?

    // The currently active terminal controller, resolved through the tab group
    var activeTerminalController: TerminalController? {
        guard let path = activeProjectPath else { return nil }
        return projectTabs[path]?.activeTab?.controller
    }

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
        window.title = "GhostCode"
        window.minSize = NSSize(width: 1200, height: 750)
        window.tabbingMode = .disallowed

        super.init(window: window)
        window.delegate = self

        setupSplitView()
        showStartupScreen()

        // Restore saved frame after all subviews are set up, so the split
        // view layout doesn't override the restored geometry.
        window.setFrameAutosaveName("GhostCodeMainWindow")
        if !window.setFrameUsingName("GhostCodeMainWindow") {
            window.center()
        }

        // Ghostty tab action notifications
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(onGhosttyNewTab(_:)),
                           name: Ghostty.Notification.ghosttyNewTab, object: nil)
        center.addObserver(self, selector: #selector(onGhosttyGotoTab(_:)),
                           name: Ghostty.Notification.ghosttyGotoTab, object: nil)
        center.addObserver(self, selector: #selector(onGhosttyMoveTab(_:)),
                           name: .ghosttyMoveTab, object: nil)
        center.addObserver(self, selector: #selector(onGhosttyCloseTab(_:)),
                           name: .ghosttyCloseTab, object: nil)

        // Bridge tracker emissions into the project store.
        // .scan carries (previous, current) so the sink only reacts to changed paths.
        attentionBridgeCancellable = attentionTracker.$attentionProjects
            .scan((Set<String>(), Set<String>())) { acc, current in (acc.1, current) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] previous, current in
                let changed = previous.symmetricDifference(current)
                for path in changed {
                    self?.projectStore.setAttention(path, hasAttention: current.contains(path))
                }
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
                pulseClock: pulseClock,
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
        leftView.preferredContentSize = NSSize(width: 300, height: 0)

        // Center: terminal or startup screen
        let centerVC = NSViewController()
        centerVC.view = centerContainer
        let centerItem = NSSplitViewItem(viewController: centerVC)
        centerItem.minimumThickness = 400

        // Right sidebar: command palette
        let rightView = NSHostingController(
            rootView: GhostCodeCommandPaletteView(
                store: commandStore,
                state: commandPaletteState,
                onItemAction: { [weak self] action in
                    guard let self else { return }
                    switch action {
                    case .sendText(let text, let sendEnter):
                        self.sendTextToActiveTerminal(text, sendEnter: sendEnter)
                    case .launchProcess(let executablePath, let arguments):
                        guard let projectPath = self.activeProjectPath else { return }
                        ExecutableLauncher.launch(
                            executablePath: executablePath,
                            projectPath: projectPath,
                            arguments: arguments
                        ) { [weak self] path, reason in
                            self?.presentLaunchFailure(executablePath: path, reason: reason)
                        }
                    }
                }
            )
        )
        rightView.sizingOptions = []
        rightSidebarItem = NSSplitViewItem(viewController: rightView)
        rightSidebarItem.minimumThickness = 160
        rightSidebarItem.maximumThickness = 340
        rightSidebarItem.canCollapse = true
        rightView.preferredContentSize = NSSize(width: 340, height: 0)

        splitViewController.addSplitViewItem(leftSidebarItem)
        splitViewController.addSplitViewItem(centerItem)
        splitViewController.addSplitViewItem(rightSidebarItem)

        window?.contentViewController = splitViewController

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Cmd+Shift shortcuts
            if flags == [.command, .shift] {
                // Use keyCode for bracket keys since charactersIgnoringModifiers
                // preserves Shift (Shift+[ = '{', not '[')
                let keyCode = event.keyCode

                switch keyCode {
                case 33: // [ key — previous tab (wraps around)
                    if let projectPath = self.activeProjectPath,
                       let tabGroup = self.projectTabs[projectPath],
                       tabGroup.tabs.count > 1 {
                        tabGroup.gotoTab(GHOSTTY_GOTO_TAB_PREVIOUS.rawValue)
                        if let project = self.projectStore.project(forPath: projectPath) {
                            self.showProjectTerminals(for: project)
                        }
                        return nil
                    }
                case 30: // ] key — next tab (wraps around)
                    if let projectPath = self.activeProjectPath,
                       let tabGroup = self.projectTabs[projectPath],
                       tabGroup.tabs.count > 1 {
                        tabGroup.gotoTab(GHOSTTY_GOTO_TAB_NEXT.rawValue)
                        if let project = self.projectStore.project(forPath: projectPath) {
                            self.showProjectTerminals(for: project)
                        }
                        return nil
                    }
                default:
                    break
                }

                switch event.charactersIgnoringModifiers {
                case "l", "L":
                    self.toggleLeftSidebar(nil)
                    return nil
                case "r", "R":
                    self.toggleRightSidebar(nil)
                    return nil
                case "d", "D":
                    // Disable Cmd+Shift+D (new_split:down)
                    if self.activeProjectPath != nil { return nil }
                case "w", "W":
                    // Disable Cmd+Shift+W (close_window — not applicable)
                    if self.activeProjectPath != nil { return nil }
                case "p", "P":
                    // Disable Cmd+Shift+P (Ghostty command palette — not applicable)
                    if self.activeProjectPath != nil { return nil }
                default:
                    break
                }
            }

            // Disable Cmd+Alt+I (Ghostty inspector — not applicable)
            if flags == [.command, .option],
               event.charactersIgnoringModifiers?.lowercased() == "i",
               self.activeProjectPath != nil {
                return nil
            }

            // Cmd-only shortcuts
            if flags == [.command], let char = event.charactersIgnoringModifiers {
                // Cmd+Number (tab switching)
                if let digit = char.first?.wholeNumberValue,
                   digit >= 1, digit <= 9,
                   let projectPath = self.activeProjectPath,
                   let tabGroup = self.projectTabs[projectPath],
                   !tabGroup.isEmpty {
                    let targetIndex = digit == 9
                        ? tabGroup.tabs.count - 1
                        : min(digit - 1, tabGroup.tabs.count - 1)
                    self.selectTab(at: targetIndex, projectPath: projectPath)
                    return nil
                }

                // Cmd+W (close tab)
                if char == "w",
                   let projectPath = self.activeProjectPath,
                   let tabGroup = self.projectTabs[projectPath],
                   !tabGroup.isEmpty {
                    self.closeTab(at: tabGroup.activeTabIndex, projectPath: projectPath)
                    return nil
                }

                // Cmd+T (new shell tab)
                if char == "t", let projectPath = self.activeProjectPath {
                    self.createShellTab(projectPath: projectPath)
                    return nil
                }

                // Disable Cmd+N (new_window — not applicable)
                if char == "n", self.activeProjectPath != nil {
                    return nil
                }

                // Disable Cmd+D (new_split:right)
                if char == "d", self.activeProjectPath != nil {
                    return nil
                }

                // Disable Cmd+[ and Cmd+] (goto_split)
                if (char == "[" || char == "]"), self.activeProjectPath != nil {
                    return nil
                }
            }

            // Cmd+Enter (fullscreen the GhostCode window, not the terminal)
            if flags == [.command], event.keyCode == 36, self.activeProjectPath != nil {
                self.window?.toggleFullScreen(nil)
                return nil
            }

            // Disable Cmd+Shift+Alt+W (close_all_windows — not applicable)
            if flags == [.command, .shift, .option],
               event.charactersIgnoringModifiers?.lowercased() == "w",
               self.activeProjectPath != nil {
                return nil
            }

            // Disable Cmd+Alt split shortcuts (goto_split directional)
            if flags == [.command, .option], self.activeProjectPath != nil {
                let keyCode = event.keyCode
                // Arrow keys: up=126, down=125, left=123, right=124
                if keyCode == 126 || keyCode == 125 || keyCode == 123 || keyCode == 124 {
                    return nil
                }
            }

            // Cmd+Ctrl+F (fullscreen the GhostCode window — alternate)
            if flags == [.command, .control],
               event.charactersIgnoringModifiers == "f",
               self.activeProjectPath != nil {
                self.window?.toggleFullScreen(nil)
                return nil
            }

            // Disable Cmd+Ctrl split shortcuts (resize_split)
            if flags == [.command, .control], self.activeProjectPath != nil {
                let keyCode = event.keyCode
                if keyCode == 126 || keyCode == 125 || keyCode == 123 || keyCode == 124 {
                    return nil
                }
            }

            // Disable Cmd+Ctrl+= (equalize_splits)
            if flags == [.command, .control],
               event.charactersIgnoringModifiers == "=",
               self.activeProjectPath != nil {
                return nil
            }

            return event
        }
    }

    private var hasActiveTerminal: Bool {
        activeTerminalController != nil
    }

    // MARK: - Startup Screen

    private func showStartupScreen() {
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
        activeProjectPath = nil
        projectStore.setSelected(nil)
        updateRightSidebarLock()
    }

    // MARK: - Project Landing

    private func showProjectLanding(for project: Project) {
        centerContainer.subviews.forEach { $0.removeFromSuperview() }

        let globalDefault = GhostCodeConfig.loadAppConfig().defaultBinary

        let landingView = ProjectLandingView(
            project: project,
            globalDefaultBinary: globalDefault,
            onStartSession: { [weak self] in
                self?.spawnTerminal(for: project)
            },
            onResumeSession: { [weak self] in
                self?.spawnTerminal(for: project, resume: true)
            },
            onBinaryChanged: { [weak self] binary in
                self?.projectStore.setBinary(project.path, binary: binary)
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
        activeProjectPath = nil
        projectStore.setSelected(project.path)
        updateRightSidebarLock()
    }

    // MARK: - Project Activation

    private func activateProject(_ project: Project) {
        if let tabGroup = projectTabs[project.path], !tabGroup.isEmpty {
            // Check if all tabs have exited
            let allExited = tabGroup.tabs.allSatisfy { tab in
                isProcessExited(tab.controller)
            }
            if allExited {
                cleanupTabGroup(for: project.path)
                showProjectLanding(for: project)
                return
            }
            attentionTracker.clearAttention(projectPath: project.path)
            showProjectTerminals(for: project)
            return
        }

        // Already showing the landing page for this project — don't recreate it.
        if activeProjectPath == nil && projectStore.selectedPath == project.path {
            return
        }

        showProjectLanding(for: project)
    }

    private func spawnTerminal(for project: Project, resume: Bool = false) {
        Task {
            await spawnTerminalAsync(for: project, resume: resume)
        }
    }

    private func spawnTerminalAsync(for project: Project, resume: Bool) async {
        let currentProject = projectStore.project(forPath: project.path) ?? project
        let binary = currentProject.binary ?? GhostCodeConfig.loadAppConfig().defaultBinary
        let resolvedPath = await GhostCodeConfig.resolveCommand(binary.commandName)
        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = project.path
        config.hushLogin = true
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let command: String
        if resume, let resumeArg = binary.resumeArg {
            command = "\(resolvedPath) \(resumeArg)"
        } else {
            command = resolvedPath
        }
        config.command = "\(shell) -l -c 'exec \(command)'"

        let controller = TerminalController(ghostty, withBaseConfig: config)

        // Set focused surface manually since windowDidLoad won't run
        // (we embed TerminalView directly, bypassing the nib-based window).
        if case .leaf(let view) = controller.surfaceTree.root {
            controller.focusedSurface = view
        }

        let tab = TabItem(controller: controller, kind: .ai, title: binary.displayName)
        let tabGroup = ProjectTabGroup()
        tabGroup.addTab(tab)
        projectTabs[project.path] = tabGroup

        let trackedTabs = tabGroup.$tabs
            .map { items in
                items.map { item in
                    TrackedTab(
                        id: item.id,
                        kind: item.kind,
                        bellPublisher: item.controller.$bell.eraseToAnyPublisher()
                    )
                }
            }
            .eraseToAnyPublisher()
        attentionTracker.startTracking(projectPath: project.path, trackedTabs: trackedTabs)

        projectStore.setActive(project.path, active: true)
        showProjectTerminals(for: project)
        observeTabExit(tab, projectPath: project.path)
    }

    private func showProjectTerminals(for project: Project) {
        guard let tabGroup = projectTabs[project.path], !tabGroup.isEmpty else { return }

        activeProjectPath = project.path
        projectStore.setVisible(project.path)
        updateRightSidebarLock()

        // Build the new container before removing the old one to avoid a
        // visible flash. We defer the swap to the next run loop so the center
        // container has valid bounds from the previous layout pass.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let container = ProjectTerminalContainer(
                tabGroup: tabGroup,
                attentionTracker: self.attentionTracker,
                ghostty: self.ghostty,
                onNewShellTab: { [weak self] in
                    self?.createShellTab(projectPath: project.path)
                },
                onNewAITab: { [weak self] in
                    self?.createAITab(projectPath: project.path)
                },
                onCloseTab: { [weak self] index in
                    self?.closeTab(at: index, projectPath: project.path)
                },
                onSelectTab: { [weak self] index in
                    self?.selectTab(at: index, projectPath: project.path)
                },
                onCloseOtherTabs: { [weak self] index in
                    self?.closeOtherTabs(keepIndex: index, projectPath: project.path)
                }
            )
            let hostingView = NSHostingView(rootView: container.environmentObject(self.pulseClock))
            hostingView.sizingOptions = []
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

            // Cancel any pending focus transfer from a previous call
            // (e.g. rapid Cmd+T presses) so only the latest one runs.
            self.pendingFocusWork?.cancel()
            let focusWork = DispatchWorkItem { [weak self] in
                self?.transferFocusToActiveSurface(retries: 10)
            }
            self.pendingFocusWork = focusWork
            DispatchQueue.main.async(execute: focusWork)
        }
    }

    // MARK: - Tab Management

    /// Attempts to make the active terminal surface the first responder.
    /// Retries with increasing delay if the surface isn't ready yet
    /// (e.g. Metal view hasn't completed its layout pass) or if SwiftUI's
    /// focus system overrides the assignment during a layout pass.
    private func transferFocusToActiveSurface(retries: Int) {
        guard let surface = activeTerminalController?.focusedSurface,
              let window = window else { return }

        // Ensure the window is key so keyboard input reaches the terminal
        if !window.isKeyWindow {
            window.makeKeyAndOrderFront(nil)
        }

        // Surface must be in the view hierarchy with valid bounds
        if surface.window != nil, surface.bounds.width > 0 {
            window.makeFirstResponder(surface)

            // Verify focus took effect — SwiftUI layout passes can reassign
            // first responder after makeFirstResponder succeeds.
            if window.firstResponder !== surface, retries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.transferFocusToActiveSurface(retries: retries - 1)
                }
            }
        } else if retries > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.transferFocusToActiveSurface(retries: retries - 1)
            }
        }
    }

    private func selectTab(at index: Int, projectPath: String) {
        guard let tabGroup = projectTabs[projectPath] else { return }
        tabGroup.activateTab(at: index)

        // Recreate the hosting view so the Metal surface gets correct initial bounds.
        if let project = projectStore.project(forPath: projectPath) {
            showProjectTerminals(for: project)
        }
    }

    private func createShellTab(projectPath: String) {
        guard let tabGroup = projectTabs[projectPath] else { return }

        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = projectPath
        config.hushLogin = true

        let controller = TerminalController(ghostty, withBaseConfig: config)

        if case .leaf(let view) = controller.surfaceTree.root {
            controller.focusedSurface = view
        }

        let tab = TabItem(controller: controller, kind: .shell, title: "shell")
        tabGroup.addTab(tab)
        observeTabExit(tab, projectPath: projectPath)

        // Recreate the hosting view so the Metal surface gets correct initial bounds.
        if let project = projectStore.project(forPath: projectPath) {
            showProjectTerminals(for: project)
        }
    }

    private func createAITab(projectPath: String) {
        guard let tabGroup = projectTabs[projectPath] else { return }
        guard let project = projectStore.project(forPath: projectPath) else { return }

        let binary = project.binary ?? GhostCodeConfig.loadAppConfig().defaultBinary

        Task {
            let resolvedPath = await GhostCodeConfig.resolveCommand(binary.commandName)
            var config = Ghostty.SurfaceConfiguration()
            config.workingDirectory = projectPath
            config.hushLogin = true
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            config.command = "\(shell) -l -c 'exec \(resolvedPath)'"

            let controller = TerminalController(ghostty, withBaseConfig: config)

            if case .leaf(let view) = controller.surfaceTree.root {
                controller.focusedSurface = view
            }

            let tab = TabItem(controller: controller, kind: .ai, title: binary.displayName)
            tabGroup.addTab(tab)
            observeTabExit(tab, projectPath: projectPath)
            showProjectTerminals(for: project)
        }
    }

    private func closeTab(at index: Int, projectPath: String) {
        guard let tabGroup = projectTabs[projectPath],
              index >= 0, index < tabGroup.tabs.count else { return }

        let tab = tabGroup.tabs[index]

        // If the tab has a running process, confirm before closing
        if tab.controller.surfaceTree.contains(where: { $0.needsConfirmQuit }) {
            confirmCloseTab(at: index, projectPath: projectPath)
            return
        }

        closeTabImmediately(at: index, projectPath: projectPath)
    }

    private func confirmCloseTab(at index: Int, projectPath: String) {
        guard let window else { return }

        let alert = NSAlert()
        alert.messageText = "Close Terminal?"
        alert.informativeText = "The terminal still has a running process. If you close the terminal the process will be killed."
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                self?.closeTabImmediately(at: index, projectPath: projectPath)
            }
        }
    }

    private func closeTabImmediately(at index: Int, projectPath: String) {
        guard let tabGroup = projectTabs[projectPath] else { return }
        guard let removed = tabGroup.removeTab(at: index) else { return }

        exitCancellables.removeValue(forKey: removed.id)

        if tabGroup.isEmpty {
            cleanupTabGroup(for: projectPath)

            if activeProjectPath == projectPath {
                if let project = projectStore.project(forPath: projectPath) {
                    showProjectLanding(for: project)
                } else {
                    showStartupScreen()
                }
            }
        }
        updateRightSidebarLock()
    }

    private func closeOtherTabs(keepIndex: Int, projectPath: String) {
        guard let tabGroup = projectTabs[projectPath] else { return }
        guard keepIndex >= 0, keepIndex < tabGroup.tabs.count else { return }

        let keepTab = tabGroup.tabs[keepIndex]
        for tab in tabGroup.tabs where tab.id != keepTab.id {
            exitCancellables.removeValue(forKey: tab.id)
        }

        tabGroup.tabs = [keepTab]
        tabGroup.activeTabIndex = 0
        updateRightSidebarLock()
    }

    // MARK: - Tab Exit Observation

    private func observeTabExit(_ tab: TabItem, projectPath: String) {
        let tabId = tab.id
        let controller = tab.controller
        let cancellable = Timer.publish(every: 1.0, on: .main, in: .default)
            .autoconnect()
            .first(where: { [weak self] _ in
                self?.isProcessExited(controller) ?? true
            })
            .sink { [weak self] _ in
                self?.handleTabExit(tabId: tabId, projectPath: projectPath)
            }
        exitCancellables[tabId] = cancellable
    }

    private func handleTabExit(tabId: UUID, projectPath: String) {
        exitCancellables.removeValue(forKey: tabId)

        guard let tabGroup = projectTabs[projectPath] else { return }
        tabGroup.removeTab(withId: tabId)

        if tabGroup.isEmpty {
            cleanupTabGroup(for: projectPath)

            if activeProjectPath == projectPath {
                if let previousPath = projectStore.previousActiveProjectPath(excluding: projectPath),
                   let prevGroup = projectTabs[previousPath], !prevGroup.isEmpty,
                   let project = projectStore.project(forPath: previousPath) {
                    showProjectTerminals(for: project)
                } else if let project = projectStore.project(forPath: projectPath) {
                    showProjectLanding(for: project)
                } else {
                    showStartupScreen()
                }
            }
        }
        updateRightSidebarLock()
    }

    private func cleanupTabGroup(for projectPath: String) {
        attentionTracker.stopTracking(projectPath: projectPath)
        if let tabGroup = projectTabs[projectPath] {
            for tab in tabGroup.tabs {
                exitCancellables.removeValue(forKey: tab.id)
            }
        }
        projectTabs.removeValue(forKey: projectPath)
        projectStore.setActive(projectPath, active: false)
        projectStore.removeFromHistory(projectPath)
    }

    private func isProcessExited(_ controller: TerminalController) -> Bool {
        guard case .leaf(let view) = controller.surfaceTree.root else { return true }
        return view.processExited
    }

    // MARK: - Ghostty Tab Notifications

    /// Returns the project path that owns the given surface view, if any.
    private func projectPath(for surface: Ghostty.SurfaceView) -> String? {
        for (path, tabGroup) in projectTabs {
            for tab in tabGroup.tabs {
                if tab.controller.surfaceTree.contains(surface) {
                    return path
                }
            }
        }
        return nil
    }

    @objc private func onGhosttyNewTab(_ notification: Notification) {
        guard let surface = notification.object as? Ghostty.SurfaceView,
              let projectPath = projectPath(for: surface) else { return }
        createShellTab(projectPath: projectPath)
    }

    @objc private func onGhosttyGotoTab(_ notification: Notification) {
        guard let surface = notification.object as? Ghostty.SurfaceView,
              let projectPath = projectPath(for: surface),
              let tabGroup = projectTabs[projectPath] else { return }

        guard let tabEnumAny = notification.userInfo?[Ghostty.Notification.GotoTabKey],
              let tabEnum = tabEnumAny as? ghostty_action_goto_tab_e else { return }

        tabGroup.gotoTab(tabEnum.rawValue)

        if let project = projectStore.project(forPath: projectPath) {
            showProjectTerminals(for: project)
        }
    }

    @objc private func onGhosttyMoveTab(_ notification: Notification) {
        guard let surface = notification.object as? Ghostty.SurfaceView,
              let projectPath = projectPath(for: surface),
              let tabGroup = projectTabs[projectPath] else { return }

        guard let action = notification.userInfo?[Notification.Name.GhosttyMoveTabKey] as? Ghostty.Action.MoveTab else { return }
        guard action.amount != 0 else { return }

        tabGroup.moveTab(from: tabGroup.activeTabIndex, by: action.amount)
    }

    @objc private func onGhosttyCloseTab(_ notification: Notification) {
        guard let surface = notification.object as? Ghostty.SurfaceView,
              let projectPath = projectPath(for: surface),
              let tabGroup = projectTabs[projectPath] else { return }

        closeTab(at: tabGroup.activeTabIndex, projectPath: projectPath)
    }

    // MARK: - Command Execution

    /// The active binary for the current project.
    private var activeBinary: SupportedBinary {
        guard let path = projectStore.selectedPath,
              let project = projectStore.project(forPath: path) else {
            return GhostCodeConfig.loadAppConfig().defaultBinary
        }
        return project.binary ?? GhostCodeConfig.loadAppConfig().defaultBinary
    }

    private func sendTextToActiveTerminal(_ text: String, sendEnter: Bool = true) {
        if sendEnter {
            switch activeBinary.inputStrategy {
            case .rawCR:
                sendRawText(text, suffix: "\\r")
            case .pasteAndKeyEvent:
                sendPastedTextWithKeyEvent(text)
            }
        } else {
            sendRawText(text, suffix: nil)
        }
    }

    /// Send text (and optional Enter) as raw bytes directly to the PTY.
    /// Bypasses bracketed paste entirely.
    private func sendRawText(_ text: String, suffix: String?) {
        guard let surfaceView = activeTerminalController?.focusedSurface,
              let surfaceModel = surfaceView.surfaceModel else { return }

        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let payload: String
        if let suffix {
            payload = "text:\(escaped)\(suffix)"
        } else {
            payload = "text:\(escaped)"
        }
        _ = surfaceModel.perform(action: payload)
    }

    /// Paste text via bracketed paste, then send a key event for Enter.
    /// Used for apps that need proper key encoding (e.g. Kitty protocol).
    private func sendPastedTextWithKeyEvent(_ text: String) {
        guard let surfaceView = activeTerminalController?.focusedSurface,
              let surface = surfaceView.surface,
              let surfaceModel = surfaceView.surfaceModel else { return }

        let len = text.utf8CString.count
        guard len > 0 else { return }
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(len - 1))
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            surfaceModel.sendKeyEvent(Ghostty.Input.KeyEvent(key: .enter, action: .press))
            surfaceModel.sendKeyEvent(Ghostty.Input.KeyEvent(key: .enter, action: .release))
        }
    }

    // MARK: - Launch Failure

    private func presentLaunchFailure(executablePath: String, reason: String) {
        let alert = NSAlert()
        alert.messageText = "Could not launch app"
        alert.informativeText = "\(executablePath)\n\n\(reason)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
        projectStore.refreshAllGitStatus()

        // Restore focus to the active terminal surface when the window
        // regains key status (e.g. returning from another app via Cmd+Tab
        // or clicking the title bar). Without this the surface stays
        // unfocused and the user has to click on the terminal to type.
        if let window, let controller = activeTerminalController {
            if window.firstResponder == window {
                DispatchQueue.main.async { [weak self] in
                    self?.transferFocusToActiveSurface(retries: 5)
                }
            }
            DispatchQueue.main.async {
                controller.syncFocusToSurfaceTree()
            }
        }
    }

}
