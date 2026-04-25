import Foundation

/// Spawns external executables on behalf of tile clicks.
///
/// Intentionally a static helper rather than a controller method:
/// pure logic, no shared state, easily testable with a fake failure callback.
enum ExecutableLauncher {

    /// Launches `executablePath` with `projectPath` as its single argument and
    /// `projectPath` as its current working directory.
    ///
    /// - Parameters:
    ///   - executablePath: Absolute path to a binary or wrapper script. Schema validation
    ///     guarantees absolute-path-ness; this method only checks that the file
    ///     exists and is executable.
    ///   - projectPath: Absolute path to the project; passed both as `argv[1]` and as cwd.
    ///   - onFailure: Invoked on the main thread with `(executablePath, reason)` if the
    ///     pre-flight existence check fails or `Process.run()` throws.
    static func launch(
        executablePath: String,
        projectPath: String,
        fileManager: FileManager = .default,
        onFailure: @escaping (_ path: String, _ reason: String) -> Void
    ) {
        let url = URL(fileURLWithPath: executablePath)
        guard fileManager.isExecutableFile(atPath: url.path) else {
            onFailure(executablePath, "The file does not exist or is not executable.")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = url
            process.arguments = [projectPath]
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
