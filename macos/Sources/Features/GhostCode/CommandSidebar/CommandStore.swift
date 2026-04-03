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
final class CommandStore: ObservableObject {
    @Published private(set) var sections: [CommandSection]

    private let filePath: String

    init(filePath: String? = nil) {
        self.filePath = filePath ?? GhostCodeConfig.commandsFilePath
        self.sections = Self.defaultSections
        loadFromDisk()
    }

    func reload() {
        loadFromDisk()
    }

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
