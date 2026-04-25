import Foundation
import Combine

/// On-disk representation of a project entry with optional binary preference.
private struct ProjectEntry: Codable {
    let path: String
    var name: String?
    var binary: SupportedBinary?
}

/// Manages the list of GhostCode projects. Persists to JSON.
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var selectedPath: String?

    private let filePath: String
    private var activationHistory: [String] = []
    private var refreshTasks: [String: Task<Void, Never>] = [:]

    init(filePath: String? = nil) {
        self.filePath = filePath ?? GhostCodeConfig.projectsFilePath
        loadFromDisk()
    }

    // MARK: - Mutations

    func addProject(path: String) {
        guard !projects.contains(where: { $0.path == path }) else { return }
        projects.append(Project(path: path))
        saveToDisk()
    }

    func removeProject(path: String) {
        projects.removeAll { $0.path == path }
        saveToDisk()
    }

    func replaceProjects(_ newProjects: [Project]) {
        // Preserve binary and customName from existing projects
        var binaryMap: [String: SupportedBinary] = [:]
        var nameMap: [String: String] = [:]
        for project in projects {
            if let binary = project.binary {
                binaryMap[project.path] = binary
            }
            if let custom = project.customName {
                nameMap[project.path] = custom
            }
        }

        projects = newProjects.map { project in
            let binary = project.binary ?? binaryMap[project.path]
            let customName = project.customName ?? nameMap[project.path]
            var rebuilt = Project(
                path: project.path,
                customName: customName,
                state: project.state,
                binary: binary
            )
            rebuilt.gitStatus = project.gitStatus
            return rebuilt
        }
        saveToDisk()
    }

    func setActive(_ path: String, active: Bool) {
        guard let index = projects.firstIndex(where: { $0.path == path }) else { return }
        projects[index].state = active ? .activeBackground : .inactive
    }

    /// Mark a project as the currently visible terminal. Updates running state.
    func setVisible(_ path: String) {
        if let prevIndex = projects.firstIndex(where: { $0.state == .activeVisible }) {
            projects[prevIndex].state = .activeBackground
        }
        if let index = projects.firstIndex(where: { $0.path == path }) {
            projects[index].state = .activeVisible
        }
        activationHistory.removeAll { $0 == path }
        activationHistory.append(path)
        selectedPath = path
    }

    /// Select a project in the sidebar without changing its running state.
    /// Demotes any currently visible terminal to background.
    func setSelected(_ path: String?) {
        if let prevIndex = projects.firstIndex(where: { $0.state == .activeVisible }) {
            projects[prevIndex].state = .activeBackground
        }
        selectedPath = path
    }

    func updateGitStatus(path: String, status: Project.GitStatus?) {
        guard let index = projects.firstIndex(where: { $0.path == path }) else { return }
        projects[index].gitStatus = status
    }

    // MARK: - Git Status Refresh

    func refreshAllGitStatus() {
        for project in projects {
            refreshGitStatus(for: project.path)
        }
    }

    func refreshGitStatus(for path: String) {
        refreshTasks[path]?.cancel()
        refreshTasks[path] = Task {
            let status = await GitStatusProvider.fetchStatus(for: path)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                updateGitStatus(path: path, status: status)
            }
        }
    }

    func setBinary(_ path: String, binary: SupportedBinary?) {
        guard let index = projects.firstIndex(where: { $0.path == path }) else { return }
        projects[index].binary = binary
        saveToDisk()
    }

    func setName(_ path: String, name: String?) {
        guard let index = projects.firstIndex(where: { $0.path == path }) else { return }
        let existing = projects[index]
        var rebuilt = Project(
            path: existing.path,
            customName: name,
            state: existing.state,
            binary: existing.binary
        )
        // Preserve git status (initializer doesn't take it)
        rebuilt.gitStatus = existing.gitStatus
        projects[index] = rebuilt
        saveToDisk()
    }

    func project(forPath path: String) -> Project? {
        projects.first { $0.path == path }
    }

    /// Returns the most recently active project that still has a running terminal.
    func previousActiveProjectPath(excluding path: String) -> String? {
        for candidatePath in activationHistory.reversed() where candidatePath != path {
            if projects.first(where: { $0.path == candidatePath && $0.state != .inactive }) != nil {
                return candidatePath
            }
        }
        return nil
    }

    func removeFromHistory(_ path: String) {
        activationHistory.removeAll { $0 == path }
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: filePath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: filePath))
        else { return }

        // Try new format: [ProjectEntry]
        if let entries = try? JSONC.decode([ProjectEntry].self, from: data) {
            projects = entries.map {
                Project(path: $0.path, customName: $0.name, binary: $0.binary)
            }
            return
        }

        // Fall back to legacy format: [String]
        if let paths = try? JSONC.decode([String].self, from: data) {
            projects = paths.map { Project(path: $0) }
        }
    }

    private func saveToDisk() {
        let entries = projects.map { project in
            ProjectEntry(
                path: project.path,
                name: project.customName,
                binary: project.binary
            )
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
    }
}
