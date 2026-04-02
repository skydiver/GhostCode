import SwiftUI

/// The left sidebar view showing the project list.
struct ProjectListView: View {
    @ObservedObject var store: ProjectStore
    let onSelectProject: (Project) -> Void

    @State private var gitRefreshTimer = Timer.publish(
        every: GitStatusProvider.refreshInterval,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.projects) { project in
                        ProjectRow(project: project)
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
                .foregroundColor(.secondary)
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

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let git = project.gitStatus {
                    HStack(spacing: 6) {
                        Text(git.branch)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(git.displayText)
                            .font(.system(size: 11))
                            .foregroundColor(statusColor(git))
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(project.state == .activeVisible
            ? Color.accentColor.opacity(0.12)
            : Color.clear)
        .overlay(alignment: .leading) {
            if project.state == .activeVisible {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
            }
        }
    }

    private var dotColor: Color {
        switch project.state {
        case .activeVisible: return .green
        case .activeBackground: return .secondary
        case .inactive: return .secondary.opacity(0.5)
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
