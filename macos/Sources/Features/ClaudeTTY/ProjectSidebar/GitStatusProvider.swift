import Foundation

final class GitStatusProvider {
    static let refreshInterval: TimeInterval = 30
    static func fetchStatus(for path: String) async -> Project.GitStatus? { nil }
    static func parseGitStatus(statusOutput: String, aheadBehind: String) -> Project.GitStatus? { nil }
}
