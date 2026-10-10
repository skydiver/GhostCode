import Foundation

/// Provides git status for project directories by running git commands.
final class GitStatusProvider {
    static let refreshInterval: TimeInterval = 30

    /// Fetches git status for a project path asynchronously.
    static func fetchStatus(for path: String) async -> Project.GitStatus? {
        async let statusResult = runGit(["status", "--porcelain", "--branch"], in: path)
        async let aheadBehindResult = runGit(
            ["rev-list", "--left-right", "--count", "HEAD...@{upstream}"],
            in: path
        )
        async let remoteResult = runGit(["remote", "get-url", "origin"], in: path)

        let statusOutput = await statusResult
        let aheadBehind = await aheadBehindResult
        let remote = await remoteResult

        return parseGitStatus(
            statusOutput: statusOutput,
            aheadBehind: aheadBehind,
            remoteURL: remote.isEmpty ? nil : remote
        )
    }

    /// Parses the combined output of git status and rev-list into a GitStatus.
    static func parseGitStatus(statusOutput: String, aheadBehind: String, remoteURL: String? = nil) -> Project.GitStatus? {
        let lines = statusOutput.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard let branchLine = lines.first, branchLine.hasPrefix("##") else {
            return nil
        }

        // Parse branch name: "## main...origin/main" or "## main"
        let branchPart = branchLine.dropFirst(3)  // Remove "## "
        let branch: String
        if let dotRange = branchPart.range(of: "...") {
            branch = String(branchPart[..<dotRange.lowerBound])
        } else {
            branch = String(branchPart.prefix(while: { $0 != " " }))
        }

        // Count changed files (all lines except the branch line)
        let changedFiles = lines.dropFirst().count
        let isDirty = changedFiles > 0

        // Parse ahead/behind from rev-list output
        var ahead = 0
        var behind = 0
        let abLines = aheadBehind.components(separatedBy: "\n").filter { !$0.isEmpty }
        if let abLine = abLines.first {
            let parts = abLine.split(separator: "\t")
            if parts.count == 2 {
                ahead = Int(parts[0]) ?? 0
                behind = Int(parts[1]) ?? 0
            }
        }

        return Project.GitStatus(
            branch: branch,
            isDirty: isDirty,
            changedFileCount: changedFiles,
            ahead: ahead,
            behind: behind,
            remoteURL: remoteURL
        )
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

    /// Runs a git command in the given directory and returns stdout.
    private static func runGit(_ args: [String], in directory: String) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = makeGitProcess(args, in: directory)
                let stdout = Pipe()
                process.standardOutput = stdout
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    // Drain before waiting: git blocks once the pipe buffer is full.
                    let data = stdout.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }
}
