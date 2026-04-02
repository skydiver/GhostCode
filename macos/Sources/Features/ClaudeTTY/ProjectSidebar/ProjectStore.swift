import Foundation
import Combine

final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []

    init(filePath: String? = nil) {}
    func addProject(path: String) {}
    func removeProject(path: String) {}
    func setActive(_ path: String, active: Bool) {}
    func setVisible(_ path: String) {}
    func updateGitStatus(path: String, status: Project.GitStatus) {}
    func project(forPath path: String) -> Project? { nil }
    var previousActiveProjectPath: String? { nil }
}
