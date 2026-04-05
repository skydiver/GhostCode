import SwiftUI

/// The left sidebar view showing the project list.
struct ProjectListView: View {
    @ObservedObject var store: ProjectStore
    let onSelectProject: (Project) -> Void

    @State private var gitRefreshTimer = Timer.publish(
        every: GitStatusProvider.refreshInterval,
        on: .main,
        in: .default
    ).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Text("Projects")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.05))
                .overlay(alignment: .top) {
                    Color.white.opacity(0.06)
                        .frame(height: 1)
                }
                .overlay(alignment: .bottom) {
                    Color.black.opacity(0.15)
                        .frame(height: 1)
                }

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.projects) { project in
                        ProjectRow(project: project, isSelected: store.selectedPath == project.path)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelectProject(project)
                            }
                            .contextMenu {
                                Button("Open in Finder") {
                                    NSWorkspace.shared.selectFile(
                                        nil,
                                        inFileViewerRootedAtPath: project.path
                                    )
                                }
                                Button("Copy Path") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(
                                        project.path,
                                        forType: .string
                                    )
                                }
                                if let gitHubURL = project.gitStatus?.gitHubURL {
                                    Button("Open on GitHub") {
                                        NSWorkspace.shared.open(gitHubURL)
                                    }
                                }
                                Divider()
                                openWithMenuContent(for: project)
                                Divider()
                                Button("Remove Project", role: .destructive) {
                                    store.removeProject(path: project.path)
                                }
                            }
                    }
                }
            }

            Divider()

            Button(action: addProject) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Add Project")
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .frame(minWidth: 180, maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
        }
        .onReceive(gitRefreshTimer) { _ in
            refreshAllGitStatus()
        }
        .onAppear {
            refreshAllGitStatus()
        }
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a project directory"

        if panel.runModal() == .OK, let url = panel.url {
            store.addProject(path: url.path)
            refreshGitStatus(for: url.path)
        }
    }

    private func refreshAllGitStatus() {
        for project in store.projects {
            refreshGitStatus(for: project.path)
        }
    }

    private func isAppInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    @ViewBuilder
    private func openWithMenuContent(for project: Project) -> some View {
        let hasGhostty = isAppInstalled("com.mitchellh.ghostty")
        let hasVSCode = isAppInstalled("com.microsoft.VSCode")
        let hasTower = project.gitStatus != nil && isAppInstalled("com.fournova.Tower3")

        if hasGhostty || hasVSCode || hasTower {
            Menu("Open in") {
                if hasGhostty {
                    Button("Ghostty") {
                        openWith("com.mitchellh.ghostty", path: project.path)
                    }
                }
                if hasVSCode {
                    Button("Visual Studio Code") {
                        openWith("com.microsoft.VSCode", path: project.path)
                    }
                }
                if hasTower {
                    Button("Tower") {
                        openWith("com.fournova.Tower3", path: project.path)
                    }
                }
            }
        }
    }

    private func openWith(_ bundleID: String, path: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleID
        ) else { return }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    private func refreshGitStatus(for path: String) {
        Task {
            if let status = await GitStatusProvider.fetchStatus(for: path) {
                await MainActor.run {
                    store.updateGitStatus(path: path, status: status)
                }
            }
        }
    }
}

/// A single row in the project list.
struct ProjectRow: View {
    let project: Project
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            stateIndicator
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let git = project.gitStatus {
                    HStack(spacing: 6) {
                        Text(git.branch)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(git.displayText)
                            .font(.system(size: 11))
                            .foregroundStyle(statusColor(git))
                    }
                } else {
                    Text("no repo")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected
            ? Color.accentColor.opacity(0.12)
            : Color.clear)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
            }
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch project.state {
        case .activeVisible:
            Circle().fill(.green)
        case .activeBackground:
            Circle()
                .stroke(.green, lineWidth: 1.5)
        case .inactive:
            Circle().fill(Color.secondary.opacity(0.5))
        }
    }

    private func statusColor(_ git: Project.GitStatus) -> Color {
        if !git.isDirty && git.ahead == 0 && git.behind == 0 {
            return .green
        }
        if git.isDirty { return .yellow }
        return .blue
    }
}
