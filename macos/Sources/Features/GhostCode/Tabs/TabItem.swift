import Foundation

enum TabKind {
    case ai
    case shell
}

/// A single terminal tab within a project.
struct TabItem: Identifiable {
    let id: UUID
    let controller: TerminalController
    let kind: TabKind
    var title: String

    init(controller: TerminalController, kind: TabKind, title: String) {
        self.id = UUID()
        self.controller = controller
        self.kind = kind
        self.title = title
    }
}
