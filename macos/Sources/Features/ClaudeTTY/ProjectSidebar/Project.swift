import Foundation

struct Project: Identifiable, Equatable {
    let id: String
    let path: String
    let name: String
    var state: State = .inactive

    enum State: Equatable {
        case inactive, activeBackground, activeVisible
    }

    struct GitStatus: Equatable {
        let branch: String
        let isDirty: Bool
        let changedFileCount: Int
        let ahead: Int
        let behind: Int
    }

    var gitStatus: GitStatus?

    init(path: String, state: State = .inactive) {
        self.id = path
        self.path = path
        self.name = URL(fileURLWithPath: path).lastPathComponent
        self.state = state
    }
}
