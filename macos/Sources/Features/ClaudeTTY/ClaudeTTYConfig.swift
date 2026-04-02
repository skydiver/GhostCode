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
}
