import Foundation
import AppKit

/// A single command button in the palette.
struct CommandItem: Codable, Identifiable {
    var id: String { label }
    let label: String
    let text: String
}

/// A named section of command buttons.
struct CommandSection: Codable, Identifiable {
    var id: String { name }
    let name: String
    let items: [CommandItem]
}

/// Persistence wrapper for the command palette configuration.
struct CommandConfig: Codable {
    let sections: [CommandSection]
}

/// Loads and manages command palette sections from JSON.
/// Watches the backing file for changes and reloads automatically.
final class CommandStore: ObservableObject {
    @Published private(set) var sections: [CommandSection]

    private let filePath: String
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var watchedFD: Int32 = -1

    init(filePath: String? = nil) {
        self.filePath = filePath ?? GhostCodeConfig.commandsFilePath
        self.sections = Self.defaultSections
        loadFromDisk()
        startWatching()
    }

    deinit {
        stopWatching()
    }

    func reload() {
        loadFromDisk()
    }

    // MARK: - File Watching

    private func startWatching() {
        stopWatching()

        let fd = open(filePath, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedFD = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            self.loadFromDisk()

            // Atomic saves delete/rename the original file.
            // Re-establish the watch on the new file.
            if flags.contains(.delete) || flags.contains(.rename) {
                self.startWatching()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        fileWatcher = source
    }

    private func stopWatching() {
        fileWatcher?.cancel()
        fileWatcher = nil
        watchedFD = -1
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: filePath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let config = try? JSONDecoder().decode(CommandConfig.self, from: data)
        else {
            sections = Self.defaultSections
            return
        }
        sections = config.sections
    }

    /// Opens the commands.json file in the system default editor.
    func openInEditor() {
        if !FileManager.default.fileExists(atPath: filePath) {
            let config = CommandConfig(sections: Self.defaultSections)
            if let data = try? JSONEncoder().encode(config) {
                if let jsonObject = try? JSONSerialization.jsonObject(with: data),
                   let prettyData = try? JSONSerialization.data(
                       withJSONObject: jsonObject,
                       options: [.prettyPrinted, .sortedKeys]
                   ) {
                    try? prettyData.write(to: URL(fileURLWithPath: filePath))
                }
            }
            startWatching()
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: filePath))
    }

    static let defaultSections: [CommandSection] = [
        CommandSection(name: "Slash Commands", items: [
            CommandItem(label: "/commit", text: "/commit"),
            CommandItem(label: "/review-pr", text: "/review-pr"),
            CommandItem(label: "/help", text: "/help"),
            CommandItem(label: "/clear", text: "/clear"),
        ]),
        CommandSection(name: "Skills", items: [
            CommandItem(label: "/brainstorm", text: "/brainstorm"),
            CommandItem(label: "/debug", text: "/debug"),
            CommandItem(label: "/tdd", text: "/tdd"),
            CommandItem(label: "/shipit", text: "/shipit"),
        ]),
        CommandSection(name: "Snippets", items: [
            CommandItem(label: "Fix failing tests", text: "run the tests, find what's failing, and fix it"),
            CommandItem(label: "Explain this project", text: "read the codebase and explain the architecture"),
        ]),
    ]
}
