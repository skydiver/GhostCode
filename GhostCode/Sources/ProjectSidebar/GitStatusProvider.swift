import Foundation

/// Provides git status for project directories by running git commands.
final class GitStatusProvider {
    static let refreshInterval: TimeInterval = 30
    /// A git call that takes longer (e.g. a hung network mount) is terminated.
    private static let gitTimeout: TimeInterval = 10

    /// Fetches git status for a project path asynchronously.
    static func fetchStatus(for path: String) async -> Project.GitStatus? {
        async let statusResult = runGit(["status", "--porcelain=v2", "--branch"], in: path)
        async let remoteResult = runGit(["remote", "get-url", "origin"], in: path)

        let statusOutput = await statusResult
        let remote = await remoteResult

        return parseGitStatus(
            statusOutput: statusOutput,
            remoteURL: remote.isEmpty ? nil : remote
        )
    }

    /// Parses `git status --porcelain=v2 --branch` output into a GitStatus.
    ///
    /// Header lines start with `#` (`# branch.head main`, `# branch.ab +2 -1`);
    /// every other line is one changed, unmerged or untracked path.
    static func parseGitStatus(statusOutput: String, remoteURL: String? = nil) -> Project.GitStatus? {
        var head: String?
        var oid: String?
        var ahead = 0
        var behind = 0
        var changedFiles = 0

        for line in statusOutput.split(separator: "\n") {
            if let value = headerValue(line, key: "branch.head") {
                head = value
            } else if let value = headerValue(line, key: "branch.oid") {
                oid = value
            } else if let value = headerValue(line, key: "branch.ab") {
                // "+<ahead> -<behind>"
                let counts = value.split(separator: " ").map { Int($0.dropFirst()) ?? 0 }
                if counts.count == 2 {
                    ahead = counts[0]
                    behind = counts[1]
                }
            } else if !line.hasPrefix("#") {
                changedFiles += 1
            }
        }

        guard var branch = head else { return nil }
        if branch == "(detached)", let oid {
            branch = String(oid.prefix(7))
        }

        return Project.GitStatus(
            branch: branch,
            isDirty: changedFiles > 0,
            changedFileCount: changedFiles,
            ahead: ahead,
            behind: behind,
            remoteURL: remoteURL
        )
    }

    private static func headerValue(_ line: Substring, key: String) -> String? {
        let prefix = "# \(key) "
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count))
    }

    /// Builds the git invocation for a project directory. Repository config is
    /// untrusted: `core.fsmonitor` would run a repo-chosen command on every poll,
    /// and optional locks would make polling contend for the user's `index.lock`.
    static func makeGitProcess(_ args: [String], in directory: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "core.fsmonitor=false", "-C", directory] + args
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = environment
        return process
    }

    /// Runs a git command in the given directory and returns stdout, or "" on failure.
    private static func runGit(_ args: [String], in directory: String) async -> String {
        let process = makeGitProcess(args, in: directory)
        guard let data = await ProcessRunner.output(of: process, timeout: gitTimeout) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
