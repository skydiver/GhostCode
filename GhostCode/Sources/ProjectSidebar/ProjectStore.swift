import Foundation
import Combine
import os

private let logger = Logger(subsystem: "com.flydev.ghostcode", category: "projects")

/// On-disk representation of a project entry with optional binary preference.
private struct ProjectEntry: Codable {
    let path: String
    var name: String?
    var binary: SupportedBinary?
}

/// Manages the list of GhostCode projects. Persists to JSON.
@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var selectedPath: String?
    @Published private(set) var lastRemovedPaths: [String] = []
    /// Set when the projects file exists but could not be read. Saving is then
    /// disabled, so the user's file is never replaced by a partial list.
    private(set) var loadError: Error?

    private let filePath: String
    private var activationHistory: [String] = []
    private var refreshTasks: [String: Task<Void, Never>] = [:]

    init(filePath: String? = nil) {
        self.filePath = filePath ?? GhostCodeConfig.projectsFilePath
        loadFromDisk()
    }

    // MARK: - Mutations

    /// Adds a project folder. `/a/b`, `/a/b/` and `/a/x/../b` are the same project.
    /// Paths that exist but aren't directories are rejected; missing paths are
    /// accepted (e.g. a project on an unmounted volume).
    func addProject(path: String) {
        let path = URL(fileURLWithPath: path).standardizedFileURL.path
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue {
            logger.error("Not adding \(path, privacy: .public): not a directory")
            return
        }
        guard !projects.contains(where: { $0.path == path }) else { return }
        projects.append(Project(path: path))
        saveToDisk()
    }

    func removeProject(path: String) {
        projects.removeAll { $0.path == path }
        refreshTasks.removeValue(forKey: path)?.cancel()
        saveToDisk()
    }

    /// Update a project's attention indicator. Runtime-only — does not save to disk.
    func setAttention(_ path: String, hasAttention: Bool) {
        guard let index = projects.firstIndex(where: { $0.path == path }) else { return }
        guard projects[index].hasAttention != hasAttention else { return }
        projects[index].hasAttention = hasAttention
    }

    /// Applies an edited list (order, removals, names). Runtime state — running
    /// state, git status, attention — comes from the current store, not from the
    /// edit snapshot, since terminals may have started or exited while editing.
    func replaceProjects(_ newProjects: [Project]) {
        let newPaths = Set(newProjects.map(\.path))
        let removed = projects.map(\.path).filter { !newPaths.contains($0) }
        let current = Dictionary(projects.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })

        projects = newProjects.map { project in
            let existing = current[project.path]
            var rebuilt = Project(
                path: project.path,
                customName: project.customName ?? existing?.customName,
                state: existing?.state ?? project.state,
                binary: project.binary ?? existing?.binary
            )
            rebuilt.gitStatus = existing?.gitStatus ?? project.gitStatus
            rebuilt.hasAttention = existing?.hasAttention ?? false
            return rebuilt
        }
        saveToDisk()

        if !removed.isEmpty {
            lastRemovedPaths = removed
        }
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
            // A cancelled task has already been replaced or its project removed.
            guard !Task.isCancelled else { return }
            updateGitStatus(path: path, status: status)
            refreshTasks.removeValue(forKey: path)
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
        // Preserve runtime state the initializer doesn't take
        rebuilt.gitStatus = existing.gitStatus
        rebuilt.hasAttention = existing.hasAttention
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
        guard FileManager.default.fileExists(atPath: filePath) else { return }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            projects = try Self.decodeProjects(from: data)
        } catch {
            loadError = error
            logger.error("Could not read \(self.filePath, privacy: .public); project changes will not be saved: \(error)")
        }
    }

    private static func decodeProjects(from data: Data) throws -> [Project] {
        do {
            return try JSONC.decode([ProjectEntry].self, from: data).map {
                Project(path: $0.path, customName: $0.name, binary: $0.binary)
            }
        } catch {
            // Legacy format: [String]. Report the current format's error if both fail.
            guard let paths = try? JSONC.decode([String].self, from: data) else { throw error }
            return paths.map { Project(path: $0) }
        }
    }

    private func saveToDisk() {
        guard loadError == nil else {
            logger.error("Not saving \(self.filePath, privacy: .public): it could not be read at launch")
            return
        }
        let entries = projects.map { project in
            ProjectEntry(
                path: project.path,
                name: project.customName,
                binary: project.binary
            )
        }
        // Readable for hand edits. Comments in the file are not preserved.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(entries)
            try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
        } catch {
            logger.error("Could not save \(self.filePath, privacy: .public): \(error)")
        }
    }
}
