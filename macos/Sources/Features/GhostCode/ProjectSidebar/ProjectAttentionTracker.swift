import Foundation
import Combine

/// Bridges per-AI-tab bell state up to per-project "attention pending" state.
///
/// Two layers:
///   - Core state machine (`setBell`, `clearAttention`, `stopTracking`, `reconcileTabs`)
///     — pure, synchronous, fully unit-testable.
///   - Combine wiring (added in a later task) — translates per-tab bell publishers
///     into core API calls.
///
/// All mutations happen on the main run loop; the wiring layer pipes events
/// through `.receive(on: DispatchQueue.main)` before invoking the core API.
final class ProjectAttentionTracker: ObservableObject {

    /// Project paths that currently have at least one AI tab waiting on the user.
    @Published private(set) var attentionProjects: Set<String> = []

    /// Tab UUIDs (across all projects) that currently have a pending bell.
    @Published private(set) var attentionTabs: Set<UUID> = []

    // MARK: - Core state

    private var tabsByProject: [String: Set<UUID>] = [:]

    /// Wiring-layer storage. Populated by a later task.
    var cancellablesByProject: [String: Set<AnyCancellable>] = [:]

    // MARK: - Core API

    /// Record bell state for a single tab. Non-AI tabs are ignored.
    func setBell(projectPath: String, tabId: UUID, isAI: Bool, hasBell: Bool) {
        guard isAI else { return }
        if hasBell {
            attentionTabs.insert(tabId)
            tabsByProject[projectPath, default: []].insert(tabId)
            attentionProjects.insert(projectPath)
        } else {
            attentionTabs.remove(tabId)
            guard var tabs = tabsByProject[projectPath] else { return }
            tabs.remove(tabId)
            if tabs.isEmpty {
                tabsByProject.removeValue(forKey: projectPath)
                attentionProjects.remove(projectPath)
            } else {
                tabsByProject[projectPath] = tabs
            }
        }
    }

    /// Dismiss every pending tab for a project (e.g. on user activation).
    func clearAttention(projectPath: String) {
        guard let tabs = tabsByProject.removeValue(forKey: projectPath) else { return }
        for id in tabs { attentionTabs.remove(id) }
        attentionProjects.remove(projectPath)
    }

    /// Drop pending UUIDs that no longer correspond to a live tab.
    /// Called on tab list mutations to avoid ghost dots.
    func reconcileTabs(projectPath: String, liveTabIds: Set<UUID>) {
        guard var tabs = tabsByProject[projectPath] else { return }
        let stale = tabs.subtracting(liveTabIds)
        guard !stale.isEmpty else { return }
        for id in stale { attentionTabs.remove(id) }
        tabs.subtract(stale)
        if tabs.isEmpty {
            tabsByProject.removeValue(forKey: projectPath)
            attentionProjects.remove(projectPath)
        } else {
            tabsByProject[projectPath] = tabs
        }
    }

    /// Stop tracking a project. Drops Combine subscriptions and clears state.
    func stopTracking(projectPath: String) {
        clearAttention(projectPath: projectPath)
        cancellablesByProject.removeValue(forKey: projectPath)
    }
}
