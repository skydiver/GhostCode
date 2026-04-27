import Foundation

/// Spawns external executables on behalf of tile clicks.
///
/// Intentionally a static helper rather than a controller method:
/// pure logic, no shared state, easily testable with a fake failure callback.
enum ExecutableLauncher {

    /// Placeholder token that, anywhere it appears in an `arguments` element,
    /// is replaced with the absolute project path before the process is spawned.
    static let pathPlaceholder = "{{path}}"

    /// Launches `executablePath` with either the supplied `arguments` (after
    /// `{{path}}` substitution) or the legacy `[projectPath]` argv when none
    /// are provided. The process's current working directory is always set to
    /// `projectPath`.
    ///
    /// - Parameters:
    ///   - executablePath: Absolute path to a binary or wrapper script. Schema validation
    ///     guarantees absolute-path-ness; this method only checks that the file
    ///     exists and is executable.
    ///   - projectPath: Absolute path to the project; used as cwd and as the
    ///     substitution value for the `{{path}}` placeholder.
    ///   - arguments: Optional argv template. When `nil`, argv defaults to
    ///     `[projectPath]` (legacy behavior). When non-nil — including an empty
    ///     array — argv is exactly the supplied template with `{{path}}` replaced.
    ///   - onFailure: Invoked on the main thread with `(executablePath, reason)` if the
    ///     pre-flight existence check fails or `Process.run()` throws.
    static func launch(
        executablePath: String,
        projectPath: String,
        arguments: [String]? = nil,
        fileManager: FileManager = .default,
        onFailure: @escaping (_ path: String, _ reason: String) -> Void
    ) {
        let url = URL(fileURLWithPath: executablePath)
        guard fileManager.isExecutableFile(atPath: url.path) else {
            onFailure(executablePath, "The file does not exist or is not executable.")
            return
        }

        let resolvedArgs: [String]
        if let template = arguments {
            resolvedArgs = template.map { $0.replacingOccurrences(of: pathPlaceholder, with: projectPath) }
        } else {
            resolvedArgs = [projectPath]
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = url
            process.arguments = resolvedArgs
            process.currentDirectoryURL = URL(fileURLWithPath: projectPath)

            do {
                try process.run()
                // Fire-and-forget: GUI apps; we don't wait, don't capture output.
            } catch {
                DispatchQueue.main.async {
                    onFailure(executablePath, error.localizedDescription)
                }
            }
        }
    }
}
