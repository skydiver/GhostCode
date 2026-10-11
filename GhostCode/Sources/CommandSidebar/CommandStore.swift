import Foundation
import AppKit
import os

private let logger = Logger(subsystem: "com.flydev.ghostcode", category: "commands")

/// Where the icon sits relative to the label.
/// In tile layout all four positions are honored. In flow/list only `left` and
/// `right` apply — `top` and `bottom` fall back to the layout's default (`left`).
enum IconPosition: String, Codable {
    case top, bottom, left, right
}

/// A single command button in the palette.
struct CommandItem: Codable {
    let label: String
    let text: String?
    let executable: String?
    let arguments: [String]?
    let tooltip: String?
    let autoSend: Bool?
    let icon: String?
    let iconPosition: IconPosition?

    /// Whether to send Enter after the text. Defaults to false.
    var shouldAutoSend: Bool { autoSend ?? false }

    /// Click behavior for this item.
    enum Action {
        case sendText(String, autoSend: Bool)
        case launchProcess(executablePath: String, arguments: [String]?)

        /// Whether this action can run given the current palette capabilities.
        func isEnabled(canSendText: Bool, canLaunch: Bool) -> Bool {
            switch self {
            case .sendText: return canSendText
            case .launchProcess: return canLaunch
            }
        }
    }

    var action: Action? {
        if let executable { return .launchProcess(executablePath: executable, arguments: arguments) }
        if let text       { return .sendText(text, autoSend: shouldAutoSend) }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case label, text, executable, arguments, tooltip, autoSend, icon, iconPosition
    }

    init(label: String, text: String?, executable: String? = nil,
         arguments: [String]? = nil,
         tooltip: String? = nil, autoSend: Bool? = nil,
         icon: String? = nil, iconPosition: IconPosition? = nil) {
        self.label = label
        self.text = text
        self.executable = executable
        self.arguments = arguments
        self.tooltip = tooltip
        self.autoSend = autoSend
        self.icon = icon
        self.iconPosition = iconPosition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.label = try container.decode(String.self, forKey: .label)
        self.text = try container.decodeIfPresent(String.self, forKey: .text)
        self.executable = try container.decodeIfPresent(String.self, forKey: .executable)
        self.arguments = try container.decodeIfPresent([String].self, forKey: .arguments)
        self.tooltip = try container.decodeIfPresent(String.self, forKey: .tooltip)
        self.autoSend = try container.decodeIfPresent(Bool.self, forKey: .autoSend)
        self.icon = try container.decodeIfPresent(String.self, forKey: .icon)
        self.iconPosition = try container.decodeIfPresent(IconPosition.self, forKey: .iconPosition)

        // Validation: exactly one of text/executable.
        switch (text, executable) {
        case (nil, nil):
            throw DecodingError.dataCorruptedError(
                forKey: .label, in: container,
                debugDescription: "Item '\(label)' has neither 'text' nor 'executable'."
            )
        case (.some, .some):
            throw DecodingError.dataCorruptedError(
                forKey: .label, in: container,
                debugDescription: "Item '\(label)' has both 'text' and 'executable'; use exactly one."
            )
        default:
            break
        }

        // Validation: executable must be absolute.
        if let exec = executable, !exec.hasPrefix("/") {
            throw DecodingError.dataCorruptedError(
                forKey: .executable, in: container,
                debugDescription: "Item '\(label)' executable '\(exec)' must be an absolute path (start with '/')."
            )
        }

        // Validation: arguments only makes sense with executable.
        if arguments != nil, executable == nil {
            throw DecodingError.dataCorruptedError(
                forKey: .arguments, in: container,
                debugDescription: "Item '\(label)' has 'arguments' but no 'executable'; arguments only apply to executable items."
            )
        }
    }

    /// Resolves the effective icon position for the section's layout.
    /// Tiles honor all four positions (default `top`); flow and list honor
    /// only `left` / `right` (default `left`) and silently ignore `top` / `bottom`.
    func resolvedIconPosition(for layout: SectionLayout) -> IconPosition {
        switch layout {
        case .tiles:
            return iconPosition ?? .top
        case .flow, .list:
            switch iconPosition {
            case .right: return .right
            case .left, .top, .bottom, .none: return .left
            }
        }
    }
}

/// Layout style for a command section.
enum SectionLayout: String, Codable {
    case flow   // compact, wrapping chips (default)
    case list   // full-width stacked items
    case tiles  // 2-column grid of fixed-height rectangles
}

/// A named section of command buttons.
struct CommandSection: Codable {
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
    /// Why the last load failed, or nil. The palette keeps the last valid sections.
    @Published private(set) var loadError: String?

    private let filePath: String
    private var fileWatcher: DispatchSourceFileSystemObject?

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

    /// Watches the file itself, or its directory while the file is missing.
    /// After a delete or rename (atomic saves, editors that rewrite in place)
    /// the file can be absent for a moment or for good; watching the directory
    /// picks it up whenever it comes back, so live reload never stops.
    private func startWatching() {
        stopWatching()

        let fileFD = open(filePath, O_EVTONLY)
        if fileFD >= 0 {
            watch(fileFD, events: [.write, .delete, .rename]) { [weak self] flags in
                guard let self else { return }
                self.loadFromDisk()
                if flags.contains(.delete) || flags.contains(.rename) {
                    self.startWatching()
                }
            }
            return
        }

        let directory = (filePath as NSString).deletingLastPathComponent
        let directoryFD = open(directory, O_EVTONLY)
        guard directoryFD >= 0 else {
            logger.error("Cannot watch \(directory, privacy: .public) for \(self.filePath, privacy: .public)")
            return
        }
        watch(directoryFD, events: [.write]) { [weak self] _ in
            guard let self, FileManager.default.fileExists(atPath: self.filePath) else { return }
            self.loadFromDisk()
            self.startWatching()
        }
    }

    private func watch(
        _ fd: Int32,
        events: DispatchSource.FileSystemEvent,
        handler: @escaping (DispatchSource.FileSystemEvent) -> Void
    ) {
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: events,
            queue: .main
        )
        source.setEventHandler { handler(source.data) }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileWatcher = source
    }

    private func stopWatching() {
        fileWatcher?.cancel()
        fileWatcher = nil
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: filePath) else { return }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            sections = try JSONC.decode(CommandConfig.self, from: data).sections
            loadError = nil
        } catch {
            // Keep the last valid palette so a half-finished edit doesn't wipe it.
            let message = Self.describe(error)
            loadError = message
            logger.error("Could not load \(self.filePath, privacy: .public): \(message, privacy: .public)")
        }
    }

    /// A one-line, user-facing explanation of a load failure.
    private static func describe(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else { return error.localizedDescription }
        switch decodingError {
        case .dataCorrupted(let context):
            // Syntax errors carry the parser's detail (e.g. the offending line) underneath.
            let detail = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
            return [context.debugDescription, detail].compactMap { $0 }.joined(separator: " ")
        case .keyNotFound(let key, let context):
            return "Missing \"\(key.stringValue)\"\(location(of: context))."
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "\(context.debugDescription)\(location(of: context))"
        @unknown default:
            return error.localizedDescription
        }
    }

    private static func location(of context: DecodingError.Context) -> String {
        let path = context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }
        return path.isEmpty ? "" : " at \(path.joined(separator: "."))"
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
    /// The watcher (directory mode while the file is missing) picks up the new file.
    private func ensureFileExists() {
        guard !FileManager.default.fileExists(atPath: filePath) else { return }
        do {
            try Data(Self.defaultJSONC.utf8)
                .write(to: URL(fileURLWithPath: filePath), options: .withoutOverwriting)
        } catch {
            logger.error("Could not create \(self.filePath, privacy: .public): \(error)")
        }
    }

    // MARK: - Default JSONC Template

    private static let defaultJSONC = """
    {
        // GhostCode Command Palette
        // Full reference: https://github.com/skydiver/GhostCode/blob/HEAD/GhostCode/docs/customizations.md
        //
        // Quick schema:
        //   sections[]: { name, layout?: "flow"|"list"|"tiles", items[] }
        //   items[]:    { label, text? | executable?, arguments?, tooltip?, autoSend?, icon?, iconPosition? }
        //
        // - Use exactly one of `text` (sent to terminal) or `executable` (absolute path, spawned).
        // - `arguments`: optional argv for `executable`. Use `{{path}}` as a placeholder for the
        //   active project path. When omitted, argv defaults to `[<project_path>]`.
        // - `icon`: SF Symbol name (e.g. "hammer.fill") or "data:image/svg+xml;base64,...".
        // - `iconPosition`: tiles → top|bottom|left|right (default top); flow/list → left|right (default left).
        // - Saves reload automatically. If a save has an error, the palette keeps the last
        //   valid commands and shows the error at the top until the file is fixed.
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
            },
            {
                // App launchers — clicked tile spawns `executable`.
                // By default argv is `[<project_path>]`. Use `arguments` with the
                // `{{path}}` placeholder for apps that need flag-style invocation.
                // Edit these paths to match your installations, then uncomment.
                "name": "Apps",
                "layout": "tiles",
                "items": [
                    // { "label": "VSCode", "executable": "/usr/local/bin/code" },
                    // { "label": "Tower",  "executable": "/Applications/Tower.app/Contents/MacOS/Tower" },
                    // {
                    //     "label": "Ghostty",
                    //     "executable": "/Applications/Ghostty.app/Contents/MacOS/ghostty",
                    //     "arguments": ["--working-directory={{path}}"]
                    // }
                ]
            }
        ]
    }
    """

}
