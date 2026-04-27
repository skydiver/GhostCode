import Foundation
import Combine

/// Bridges per-AI-tab bell state up to per-project "attention pending" state.
///
/// Two layers:
///   - Core state machine (`setBell`, `clearAttention`, `stopTracking`, `reconcileTabs`)
///     — pure, synchronous, fully unit-testable.
///   - Combine wiring (`startTracking`) — translates per-tab bell publishers
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

    /// Upstream `trackedTabs` subscriptions, keyed by project path.
    /// Set once in `startTracking` and never replaced until `stopTracking`.
    private var cancellablesByProject: [String: Set<AnyCancellable>] = [:]

    /// Per-tab bell subscriptions, replaced wholesale on every snapshot update.
    private var perTabCancellablesByProject: [String: Set<AnyCancellable>] = [:]

    // MARK: - Core API

    /// Record bell state for a single tab.
    /// The wiring layer only calls this for AI tabs (kind-filtered at subscription time).
    func setBell(projectPath: String, tabId: UUID, hasBell: Bool) {
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

    /// Stop tracking a project. Drops all Combine subscriptions and clears state.
    func stopTracking(projectPath: String) {
        clearAttention(projectPath: projectPath)
        cancellablesByProject.removeValue(forKey: projectPath)
        perTabCancellablesByProject.removeValue(forKey: projectPath)
    }
}

// MARK: - Wiring layer

/// A tab as the tracker sees it. Decouples the wiring layer from `TabItem`
/// so tests can construct one directly without a real `TerminalController`.
struct TrackedTab {
    let id: UUID
    let kind: TabKind
    let bellPublisher: AnyPublisher<Bool, Never>
}

extension ProjectAttentionTracker {

    /// Begin tracking a project. Idempotent — calling twice with the same
    /// path is a no-op. Subscribes to the upstream `TrackedTab` stream and,
    /// for each AI tab in the latest snapshot, to that tab's bell publisher.
    /// On every snapshot change, stale UUIDs are reconciled and per-tab
    /// subscriptions are rebuilt.
    func startTracking(
        projectPath: String,
        trackedTabs: AnyPublisher<[TrackedTab], Never>
    ) {
        guard cancellablesByProject[projectPath] == nil else { return }

        var bag: Set<AnyCancellable> = []

        trackedTabs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tabs in
                self?.rebuildSubscriptions(projectPath: projectPath, tabs: tabs)
            }
            .store(in: &bag)

        cancellablesByProject[projectPath] = bag
    }

    private func rebuildSubscriptions(projectPath: String, tabs: [TrackedTab]) {
        let liveIds = Set(tabs.map(\.id))
        reconcileTabs(projectPath: projectPath, liveTabIds: liveIds)

        var bag: Set<AnyCancellable> = []

        for tab in tabs where tab.kind == .ai {
            let id = tab.id
            tab.bellPublisher
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] hasBell in
                    self?.setBell(projectPath: projectPath, tabId: id, hasBell: hasBell)
                }
                .store(in: &bag)
        }

        // Replace the per-tab bag wholesale — previous set is released,
        // dropping all stale per-tab subscriptions automatically.
        // The upstream trackedTabs sink in cancellablesByProject is untouched.
        perTabCancellablesByProject[projectPath] = bag
    }
}
