import Foundation
import Combine

/// On-disk representation of a project entry with optional binary preference.
private struct ProjectEntry: Codable {
    let path: String
    var binary: SupportedBinary?
}

/// Manages the list of GhostCode projects. Persists to JSON.
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var selectedPath: String?

    private let filePath: String
    private var activationHistory: [String] = []

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
        // Preserve binary preferences from existing projects
        var binaryMap: [String: SupportedBinary] = [:]
        for project in projects {
            if let binary = project.binary {
                binaryMap[project.path] = binary
            }
        }

        projects = newProjects.map { project in
            var updated = project
            if updated.binary == nil, let binary = binaryMap[project.path] {
                updated.binary = binary
            }
            return updated
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

    func updateGitStatus(path: String, status: Project.GitStatus) {
        guard let index = projects.firstIndex(where: { $0.path == path }) else { return }
        projects[index].gitStatus = status
    }

    func setBinary(_ path: String, binary: SupportedBinary?) {
        guard let index = projects.firstIndex(where: { $0.path == path }) else { return }
        projects[index].binary = binary
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
            projects = entries.map { Project(path: $0.path, binary: $0.binary) }
            return
        }

        // Fall back to legacy format: [String]
        if let paths = try? JSONC.decode([String].self, from: data) {
            projects = paths.map { Project(path: $0) }
        }
    }

    private func saveToDisk() {
        let entries = projects.map { ProjectEntry(path: $0.path, binary: $0.binary) }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
    }
}
