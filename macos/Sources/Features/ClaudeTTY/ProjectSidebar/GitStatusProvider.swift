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

        let statusOutput = await statusResult
        let aheadBehind = await aheadBehindResult

        return parseGitStatus(statusOutput: statusOutput, aheadBehind: aheadBehind)
    }

    /// Parses the combined output of git status and rev-list into a GitStatus.
    static func parseGitStatus(statusOutput: String, aheadBehind: String) -> Project.GitStatus? {
        let lines = statusOutput.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard let branchLine = lines.first, branchLine.hasPrefix("##") else {
            return nil
        }

        // Parse branch name: "## main...origin/main" or "## main"
        let branchPart = branchLine.dropFirst(3)  // Remove "## "
        let branch = String(branchPart.split(separator: ".").first ?? branchPart.prefix(while: { $0 != " " }))

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

        // Also parse from branch line if present: "## main...origin/main [ahead 2, behind 1]"
        if let bracketRange = branchLine.range(of: "\\[.*\\]", options: .regularExpression) {
            let bracketContent = branchLine[bracketRange]
            if let aheadMatch = bracketContent.range(of: "ahead (\\d+)", options: .regularExpression) {
                let num = bracketContent[aheadMatch].split(separator: " ").last.flatMap { Int($0) }
                ahead = num ?? ahead
            }
            if let behindMatch = bracketContent.range(of: "behind (\\d+)", options: .regularExpression) {
                let num = bracketContent[behindMatch].split(separator: " ").last.flatMap { Int($0) }
                behind = num ?? behind
            }
        }

        return Project.GitStatus(
            branch: branch,
            isDirty: isDirty,
            changedFileCount: changedFiles,
            ahead: ahead,
            behind: behind
        )
    }

    /// Runs a git command in the given directory and returns stdout.
    private static func runGit(_ args: [String], in directory: String) async -> String {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", directory] + args
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                let pipe = process.standardOutput as! Pipe
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            } catch {
                continuation.resume(returning: "")
            }
        }
    }
}
