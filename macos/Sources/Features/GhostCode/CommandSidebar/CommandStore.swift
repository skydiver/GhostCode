import Foundation
import AppKit

/// A single command button in the palette.
struct CommandItem: Codable, Identifiable {
    var id: String { label }
    let label: String
    let text: String
    let tooltip: String?
}

/// Layout style for a command section.
enum SectionLayout: String, Codable {
    case flow  // compact, wrapping chips
    case list  // full-width stacked items
}

/// A named section of command buttons.
struct CommandSection: Codable, Identifiable {
    var id: String { name }
    let name: String
    let layout: SectionLayout?
    let items: [CommandItem]

    var resolvedLayout: SectionLayout { layout ?? .flow }
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
        self.sections = []
        ensureFileExists()
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
              let config = try? JSONC.decode(CommandConfig.self, from: data)
        else { return }
        sections = config.sections
    }

    /// Opens the commands file in the system default editor.
    func openInEditor() {
        ensureFileExists()
        let url = URL(fileURLWithPath: filePath)
        let editor = NSWorkspace.shared.defaultApplicationURL(forExtension: url.pathExtension)
                  ?? NSWorkspace.shared.defaultTextEditor
        if let editor {
            NSWorkspace.shared.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// Creates the commands file with commented defaults if it doesn't exist.
    private func ensureFileExists() {
        guard !FileManager.default.fileExists(atPath: filePath) else { return }
        try? Self.defaultJSONC.data(using: .utf8)?
            .write(to: URL(fileURLWithPath: filePath))
        startWatching()
    }

    // MARK: - Default JSONC Template

    private static let defaultJSONC = """
    {
        // GhostCode Command Palette Configuration
        //
        // This file defines the buttons shown in the command palette sidebar.
        // Changes are picked up automatically — no need to restart the app.
        //
        // Structure:
        //   sections[]           — Array of section groups displayed top to bottom.
        //     name               — Section heading shown in the sidebar.
        //     layout (optional)  — "flow" (default): compact, wrapping chip buttons.
        //                          "list": full-width, stacked rows (better for longer labels).
        //     items[]            — Array of command buttons within the section.
        //       label            — Button text shown in the palette.
        //       text             — The text sent to the terminal when clicked.
        //                          Can be a slash command (e.g. "/commit") or a free-form
        //                          prompt (e.g. "explain this function").
        //       tooltip (optional) — Hover tooltip text shown on the button.
        "sections": [
            {
                "name": "Slash Commands",
                "items": [
                    { "label": "/commit", "text": "/commit" },
                    { "label": "/review-pr", "text": "/review-pr" },
                    { "label": "/help", "text": "/help" },
                    { "label": "/clear", "text": "/clear" }
                ]
            },
            {
                "name": "Skills",
                "items": [
                    { "label": "/brainstorm", "text": "/brainstorm" },
                    { "label": "/debug", "text": "/debug" },
                    { "label": "/tdd", "text": "/tdd" },
                    { "label": "/shipit", "text": "/shipit" }
                ]
            },
            {
                // Use "list" layout for items with longer labels or descriptions.
                "name": "Snippets",
                "layout": "list",
                "items": [
                    { "label": "Fix failing tests", "text": "run the tests, find what's failing, and fix it" },
                    { "label": "Explain this project", "text": "read the codebase and explain the architecture" }
                ]
            }
        ]
    }
    """

}
