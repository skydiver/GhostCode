import Foundation

/// Filter modes for the project sidebar.
///
/// The raw values are persisted via `@AppStorage` in `ProjectListView`;
/// do not rename cases without writing a migration for stored preferences.
enum ProjectListFilter: String, CaseIterable {
    case all
    case active

    /// Apply this filter to a project list and return the visible subset.
    func apply(to projects: [Project]) -> [Project] {
        switch self {
        case .all:
            return projects
        case .active:
            return projects.filter { $0.state != .inactive }
        }
    }

    /// The next filter in the cycle. Two-state cycle: `.all` ↔ `.active`.
    var next: ProjectListFilter {
        switch self {
        case .all:    return .active
        case .active: return .all
        }
    }
}
