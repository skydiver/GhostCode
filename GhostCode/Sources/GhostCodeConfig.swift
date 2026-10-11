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

    /// How text and Enter are delivered to the terminal for this binary.
    enum InputStrategy {
        /// Send text + `\r` as raw bytes via the `text:` binding action.
        /// No bracketed paste. Works for Claude Code and regular shells.
        case rawCR

        /// Paste text via `ghostty_surface_text` (bracketed paste), then
        /// send Enter as a key event after a short delay.
        case pasteAndKeyEvent
    }

    var inputStrategy: InputStrategy {
        switch self {
        case .claude:   return .rawCR
        case .codex:    return .pasteAndKeyEvent
        case .opencode: return .pasteAndKeyEvent
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
        guard FileManager.default.fileExists(atPath: filePath) else { return .default }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            logger.error("Could not read \(filePath, privacy: .public), using defaults: \(error)")
            return .default
        }
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
    /// Returns nil unless the shell reports a single absolute path to an executable file.
    static func resolveCommand(
        _ name: String,
        shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
        timeout: TimeInterval = 5
    ) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "command -v \(name)"]
        guard let data = await ProcessRunner.output(of: process, timeout: timeout) else {
            logger.warning("Resolving command '\(name)' failed or timed out after \(timeout) s")
            return nil
        }
        guard let path = validatedExecutablePath(fromShellOutput: String(data: data, encoding: .utf8) ?? "") else {
            logger.warning("Command '\(name)' did not resolve to an executable path")
            return nil
        }
        return path
    }

    /// Accepts `command -v` output only when it is one absolute path to an
    /// executable file. Aliases, functions and login-script output are rejected.
    static func validatedExecutablePath(fromShellOutput output: String) -> String? {
        var path = output
        if path.hasSuffix("\n") { path.removeLast() }
        guard path.hasPrefix("/"), !path.contains(where: \.isNewline) else { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: path)
        else { return nil }
        return path
    }

    /// Builds a surface command that runs `executable` through the user's login shell.
    /// Ghostty runs the result with `/bin/sh -c` and the login shell parses the inner
    /// `exec` again, so each layer is quoted separately.
    static func loginShellCommand(shell: String, executable: String, arguments: [String]) -> String {
        let inner = "exec " + ([executable] + arguments).map(Ghostty.Shell.quote).joined(separator: " ")
        return [shell, "-l", "-c", inner].map(Ghostty.Shell.quote).joined(separator: " ")
    }
}
