import Foundation
import os

private let logger = Logger(subsystem: "com.claudetty.app", category: "config")

/// Manages ClaudeTTY-specific configuration paths and layered config loading.
/// ClaudeTTY config overrides Ghostty config using the same file format.
enum ClaudeTTYConfig {
    static var configDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/claudetty"
    }

    static var configFilePath: String {
        "\(configDirectory)/config"
    }

    static var projectsFilePath: String {
        "\(configDirectory)/projects.json"
    }

    static var commandsFilePath: String {
        "\(configDirectory)/commands.json"
    }

    /// Ensures the config directory exists. Call once at app startup.
    static func ensureConfigDirectory() {
        do {
            try FileManager.default.createDirectory(
                atPath: configDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            logger.error("Failed to create ClaudeTTY config directory: \(error)")
        }
    }

    /// Resolves a command name to its absolute path using the user's login shell.
    /// Falls back to the bare command name if resolution fails.
    static func resolveCommand(_ name: String) -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "command -v \(name)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.warning("Failed to resolve command '\(name)': \(error)")
            return name
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return name
        }
        return path
    }
}
