import Foundation

/// Represents a project in the ClaudeTTY sidebar.
struct Project: Identifiable, Equatable {
    let id: String
    let path: String
    let name: String
    var state: State
    var gitStatus: GitStatus?

    enum State: Equatable {
        case inactive
        case activeBackground
        case activeVisible
    }

    struct GitStatus: Equatable {
        let branch: String
        let isDirty: Bool
        let changedFileCount: Int
        let ahead: Int
        let behind: Int

        var displayText: String {
            if !isDirty && ahead == 0 && behind == 0 {
                return "\u{2713} clean"
            }
            if isDirty {
                return "\u{25CF} \(changedFileCount) file\(changedFileCount == 1 ? "" : "s")"
            }
            var parts: [String] = []
            if ahead > 0 { parts.append("\u{2191}\(ahead)") }
            if behind > 0 { parts.append("\u{2193}\(behind)") }
            return parts.joined(separator: " ")
        }
    }

    init(path: String, state: State = .inactive) {
        self.id = path
        self.path = path
        self.name = URL(fileURLWithPath: path).lastPathComponent
        self.state = state
    }
}
