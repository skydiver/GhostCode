import Foundation
import os

private let logger = Logger(subsystem: "com.flydev.ghostcode", category: "config")

/// The set of CLI binaries GhostCode can wrap.
enum SupportedBinary: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex
    case opencode

    var id: String { rawValue }

    var commandName: String {
        switch self {
        case .claude:   return "claude"
        case .codex:    return "codex"
        case .opencode: return "opencode"
        }
    }

    var displayName: String {
        switch self {
        case .claude:   return "Claude Code"
        case .codex:    return "Codex"
        case .opencode: return "OpenCode"
        }
    }

    /// The flag appended for "Resume" sessions. Nil means resume not supported.
    var resumeArg: String? {
        switch self {
        case .claude:   return "--continue"
        case .codex:    return nil
        case .opencode: return nil
        }
    }

    /// Whether this binary stores session data the app can read.
    var supportsSessionInfo: Bool {
        switch self {
        case .claude:   return true
        case .codex, .opencode: return false
        }
    }
}

/// Manages GhostCode-specific configuration paths and layered config loading.
/// GhostCode config overrides Ghostty config using the same file format.
enum GhostCodeConfig {
    static var configDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/ghostcode"
    }

    static var configFilePath: String {
        "\(configDirectory)/config"
    }

    static var projectsFilePath: String {
        resolveConfigFile("projects")
    }

    static var commandsFilePath: String {
        resolveConfigFile("commands")
    }

    /// Returns the path for a config file, preferring `.jsonc` over `.json`.
    /// Defaults to `.jsonc` when neither exists (for new file creation).
    private static func resolveConfigFile(_ name: String) -> String {
        let jsoncPath = "\(configDirectory)/\(name).jsonc"
        let jsonPath = "\(configDirectory)/\(name).json"
        if FileManager.default.fileExists(atPath: jsoncPath) { return jsoncPath }
        if FileManager.default.fileExists(atPath: jsonPath) { return jsonPath }
        return jsoncPath
    }

    static var appConfigFilePath: String {
        "\(configDirectory)/config.json"
    }

    struct AppConfig: Codable {
        var defaultBinary: SupportedBinary

        static let `default` = AppConfig(defaultBinary: .claude)
    }

    /// Loads the GhostCode app config. Falls back to defaults if missing or malformed.
    /// - Parameter path: Override path for testing. Uses `appConfigFilePath` when nil.
    static func loadAppConfig(from path: String? = nil) -> AppConfig {
        let filePath = path ?? appConfigFilePath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else {
            return .default
        }
        return config
    }

    /// Ensures the config directory exists. Call once at app startup.
    static func ensureConfigDirectory() {
        do {
            try FileManager.default.createDirectory(
                atPath: configDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            logger.error("Failed to create GhostCode config directory: \(error)")
        }
    }

    /// Resolves a command name to its absolute path using the user's login shell.
    /// Falls back to the bare command name if resolution fails.
    static func resolveCommand(_ name: String) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
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
                    continuation.resume(returning: name)
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      !path.isEmpty else {
                    continuation.resume(returning: name)
                    return
                }
                continuation.resume(returning: path)
            }
        }
    }
}
