import Foundation
import Combine

/// Manages the list of ClaudeTTY projects. Persists to JSON.
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []

    private let filePath: String
    private var visiblePath: String?

    init(filePath: String? = nil) {
        self.filePath = filePath ?? ClaudeTTYConfig.projectsFilePath
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

    func setActive(_ path: String, active: Bool) {
        guard let index = projects.firstIndex(where: { $0.path == path }) else { return }
        projects[index].state = active ? .activeBackground : .inactive
    }

    func setVisible(_ path: String) {
        if let prevIndex = projects.firstIndex(where: { $0.state == .activeVisible }) {
            projects[prevIndex].state = .activeBackground
        }
        if let index = projects.firstIndex(where: { $0.path == path }) {
            projects[index].state = .activeVisible
        }
        visiblePath = path
    }

    func updateGitStatus(path: String, status: Project.GitStatus) {
        guard let index = projects.firstIndex(where: { $0.path == path }) else { return }
        projects[index].gitStatus = status
    }

    func project(forPath path: String) -> Project? {
        projects.first { $0.path == path }
    }

    var previousActiveProjectPath: String? {
        projects.first { $0.state == .activeBackground }?.path
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: filePath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let paths = try? JSONDecoder().decode([String].self, from: data)
        else { return }

        projects = paths.map { Project(path: $0) }
    }

    private func saveToDisk() {
        let paths = projects.map(\.path)
        guard let data = try? JSONEncoder().encode(paths) else { return }
        try? data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
    }
}
