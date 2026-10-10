import Foundation

/// Represents a project in the GhostCode sidebar.
struct Project: Identifiable, Equatable {
    let id: String
    let path: String
    let name: String
    let customName: String?
    var state: State
    var gitStatus: GitStatus?
    var binary: SupportedBinary?
    /// Runtime-only: true when at least one AI tab in this project has rung
    /// the bell since the user last activated the project. NOT persisted.
    var hasAttention: Bool = false

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
        /// The remote comes from repository config and is opened with NSWorkspace,
        /// so only an https URL on github.com is returned.
        var gitHubURL: URL? {
            guard let remote = remoteURL?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }

            // SSH: git@github.com:owner/repo.git
            let sshPrefix = "git@github.com:"
            let candidate = remote.hasPrefix(sshPrefix)
                ? "https://github.com/" + remote.dropFirst(sshPrefix.count)
                : remote

            guard let components = URLComponents(string: candidate),
                  components.scheme?.lowercased() == "https",
                  let host = components.host?.lowercased(),
                  host == "github.com" || host == "www.github.com"
            else { return nil }

            var path = components.path
            if path.hasSuffix(".git") { path.removeLast(".git".count) }

            var url = URLComponents()
            url.scheme = "https"
            url.host = host
            url.path = path
            return url.url
        }
    }

    init(
        path: String,
        customName: String? = nil,
        state: State = .inactive,
        binary: SupportedBinary? = nil
    ) {
        self.id = path
        self.path = path
        let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let folderName = URL(fileURLWithPath: path).lastPathComponent
        if trimmed.isEmpty || trimmed == folderName {
            self.customName = nil
            self.name = folderName
        } else {
            self.customName = trimmed
            self.name = trimmed
        }
        self.state = state
        self.binary = binary
    }
}
