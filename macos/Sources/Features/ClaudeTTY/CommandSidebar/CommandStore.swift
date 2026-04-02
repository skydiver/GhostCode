import Foundation

struct CommandItem: Codable, Identifiable {
    var id: String { label }
    let label: String
    let text: String
}

struct CommandSection: Codable, Identifiable {
    var id: String { name }
    let name: String
    let items: [CommandItem]
}

final class CommandStore: ObservableObject {
    @Published private(set) var sections: [CommandSection] = []
    init(filePath: String? = nil) {}
    func openInEditor() {}
}
