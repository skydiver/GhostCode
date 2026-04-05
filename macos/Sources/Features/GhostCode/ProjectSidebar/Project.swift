import Foundation

/// Represents a project in the GhostCode sidebar.
struct Project: Identifiable, Equatable {
    let id: String
    let path: String
    let name: String
    var state: State
    var gitStatus: GitStatus?
    var binary: SupportedBinary?

    enum State: Equatable {
        case inactive
        case activeBackground
        case activeVisible
    }

    struct GitStatus: Equatable {
        let branch: String
        let isDirty: Bool
        let changedFileCount: Int
        let ahead: Int
        let behind: Int
        let remoteURL: String?

        var displayText: String {
            var parts: [String] = []
            if isDirty {
                parts.append("\u{25CF} \(changedFileCount) file\(changedFileCount == 1 ? "" : "s")")
            }
            if ahead > 0 { parts.append("\u{2191}\(ahead)") }
            if behind > 0 { parts.append("\u{2193}\(behind)") }
            if parts.isEmpty { return "\u{2713} clean" }
            return parts.joined(separator: " ")
        }

        /// The HTTPS URL for viewing the repo on GitHub, or nil if not a GitHub remote.
        var gitHubURL: URL? {
            guard let remote = remoteURL else { return nil }
            let cleaned = remote.trimmingCharacters(in: .whitespacesAndNewlines)

            // SSH: git@github.com:owner/repo.git
            if cleaned.hasPrefix("git@github.com:") {
                let path = cleaned
                    .replacingOccurrences(of: "git@github.com:", with: "")
                    .replacingOccurrences(of: ".git", with: "")
                return URL(string: "https://github.com/\(path)")
            }

            // HTTPS: https://github.com/owner/repo.git
            if cleaned.contains("github.com") {
                let path = cleaned.replacingOccurrences(of: ".git", with: "")
                return URL(string: path)
            }

            return nil
        }
    }

    init(path: String, state: State = .inactive, binary: SupportedBinary? = nil) {
        self.id = path
        self.path = path
        self.name = URL(fileURLWithPath: path).lastPathComponent
        self.state = state
        self.binary = binary
    }
}
