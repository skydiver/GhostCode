import SwiftUI

/// The left sidebar view showing the project list.
struct ProjectListView: View {
    @ObservedObject var store: ProjectStore
    let onSelectProject: (Project) -> Void

    @State private var gitRefreshTimer = Timer.publish(
        every: GitStatusProvider.refreshInterval,
        on: .main,
        in: .default
    ).autoconnect()

    @State private var isEditing = false
    @State private var editingProjects: [Project] = []
    @State private var draggingProjectPath: String?
    @State private var rowMidpoints: [String: CGFloat] = [:]

    @State private var renamingPath: String?
    @State private var renameBuffer: String = ""
    @FocusState private var renameFieldFocused: Bool

    @AppStorage("ghostcode.projectListFilter")
    private var filterRawValue: String = ProjectListFilter.all.rawValue

    private var filter: ProjectListFilter {
        get { ProjectListFilter(rawValue: filterRawValue) ?? .all }
        nonmutating set { filterRawValue = newValue.rawValue }
    }

    private var visibleProjects: [Project] {
        filter.apply(to: store.projects)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(filter == .active ? "Projects · Active" : "Projects")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.05))
                .overlay(alignment: .top) {
                    Color.white.opacity(0.06)
                        .frame(height: 1)
                }
                .overlay(alignment: .bottom) {
                    Color.black.opacity(0.15)
                        .frame(height: 1)
                }

            if isEditing {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        editModeList
                    }
                    .coordinateSpace(name: "editList")
                    .onPreferenceChange(RowMidpointKey.self) { rowMidpoints = $0 }
                }
            } else {
                ScrollView {
                    if filter == .active && visibleProjects.isEmpty && !store.projects.isEmpty {
                        Text("No active projects")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else {
                        LazyVStack(spacing: 2) {
                            normalModeList
                        }
                    }
                }
            }

            Divider()

            if isEditing {
                HStack {
                    Spacer()
                    Button("Cancel") {
                        cancelEdits()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))

                    Button("Save") {
                        saveEdits()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(Color.accentColor)
                    .cornerRadius(4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else {
                HStack(spacing: 8) {
                    Button(action: addProject) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text("Add Project")
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(action: cycleFilter) {
                        Image(systemName: filter == .active
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(filter == .active ? .green : .secondary)
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.projects.isEmpty)
                    .help(filter == .active
                        ? "Showing active projects only — click to show all"
                        : "Show all projects — click to show only active")
                    .accessibilityLabel(filter == .active
                        ? "Showing active projects only"
                        : "Showing all projects")

                    Button(action: enterEditMode) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.projects.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .frame(minWidth: 180, maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
        }
        .onReceive(gitRefreshTimer) { _ in
            store.refreshAllGitStatus()
        }
        .onAppear {
            store.refreshAllGitStatus()
        }
    }

    // MARK: - Edit Mode

    @ViewBuilder
    private var editModeList: some View {
        ForEach(editingProjects) { project in
            editModeRow(project: project)
        }
    }

    private func editModeRow(project: Project) -> some View {
        let isDragging = draggingProjectPath == project.path
        return HStack(spacing: 0) {
            ProjectRow(project: project, isSelected: false, editing: true)

            Button {
                withAnimation {
                    editingProjects.removeAll { $0.id == project.id }
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
        }
        .opacity(isDragging ? 0.4 : 1.0)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: RowMidpointKey.self,
                    value: [project.path: geo.frame(in: .named("editList")).midY]
                )
            }
        )
        .overlay(alignment: .leading) {
            // Drag gesture overlay on the handle area
            Color.clear
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 5, coordinateSpace: .named("editList"))
                        .onChanged { value in
                            if draggingProjectPath == nil {
                                draggingProjectPath = project.path
                            }
                            let targetIdx = indexAt(y: value.location.y)
                            guard let srcIdx = editingProjects.firstIndex(where: { $0.path == project.path }),
                                  srcIdx != targetIdx else { return }
                            withAnimation(.easeInOut(duration: 0.15)) {
                                editingProjects.move(
                                    fromOffsets: IndexSet(integer: srcIdx),
                                    toOffset: targetIdx > srcIdx ? targetIdx + 1 : targetIdx
                                )
                            }
                        }
                        .onEnded { _ in
                            draggingProjectPath = nil
                        }
                )
        }
    }

    /// Determine the target index for a project dragged to Y position.
    private func indexAt(y: CGFloat) -> Int {
        let orderedMidpoints = editingProjects.compactMap { project in
            rowMidpoints[project.path].map { (index: editingProjects.firstIndex(of: project)!, midY: $0) }
        }.sorted { $0.midY < $1.midY }

        var targetIdx = 0
        for entry in orderedMidpoints {
            if y > entry.midY { targetIdx = entry.index + 1 }
        }
        return min(max(targetIdx, 0), editingProjects.count - 1)
    }

    // MARK: - Normal Mode

    @ViewBuilder
    private var normalModeList: some View {
        ForEach(visibleProjects) { project in
            ProjectRow(
                project: project,
                isSelected: store.selectedPath == project.path,
                renameText: renamingPath == project.path ? $renameBuffer : nil,
                renameFocus: $renameFieldFocused,
                onRenameCommit: commitRename,
                onRenameCancel: cancelRename
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if renamingPath == project.path { return }
                onSelectProject(project)
            }
            .contextMenu {
                projectContextMenu(for: project)
            }
        }
    }

    // MARK: - Actions

    private func startRename(_ project: Project) {
        renameBuffer = project.name
        renamingPath = project.path
        // Defer focus so the TextField is in the view tree first.
        DispatchQueue.main.async {
            renameFieldFocused = true
        }
    }

    private func commitRename() {
        // Pressing Esc clears renamingPath via cancelRename, which removes the
        // TextField and triggers a spurious focus-loss commit. The guard absorbs it.
        guard let path = renamingPath else { return }
        store.setName(path, name: renameBuffer)
        renamingPath = nil
        renameBuffer = ""
    }

    private func cancelRename() {
        renamingPath = nil
        renameBuffer = ""
    }

    private func cycleFilter() {
        filter = filter.next
    }

    private func enterEditMode() {
        editingProjects = store.projects
        isEditing = true
    }

    private func saveEdits() {
        store.replaceProjects(editingProjects)
        isEditing = false
    }

    private func cancelEdits() {
        editingProjects = []
        isEditing = false
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a project directory"

        if panel.runModal() == .OK, let url = panel.url {
            store.addProject(path: url.path)
            store.refreshGitStatus(for: url.path)
            // Newly added projects start as .inactive; reset the filter so the
            // user immediately sees the project they just chose.
            if filter != .all {
                filter = .all
            }
        }
    }

    @ViewBuilder
    private func projectContextMenu(for project: Project) -> some View {
        Button("Open in Finder") {
            NSWorkspace.shared.selectFile(
                nil,
                inFileViewerRootedAtPath: project.path
            )
        }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(
                project.path,
                forType: .string
            )
        }
        Button("Rename") {
            startRename(project)
        }
        if let gitHubURL = project.gitStatus?.gitHubURL {
            Button("Open on GitHub") {
                NSWorkspace.shared.open(gitHubURL)
            }
        }
    }

}

// MARK: - PreferenceKey for row midpoints

private struct RowMidpointKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - ProjectRow

/// A single row in the project list.
struct ProjectRow: View {
    let project: Project
    let isSelected: Bool
    var editing: Bool = false

    var renameText: Binding<String>? = nil
    var renameFocus: FocusState<Bool>.Binding? = nil
    var onRenameCommit: () -> Void = {}
    var onRenameCancel: () -> Void = {}

    var body: some View {
        HStack(spacing: 14) {
            if editing {
                Image(systemName: "line.horizontal.3")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 8, height: 8)
            } else {
                stateIndicator
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 3) {
                if let renameText = renameText, let renameFocus = renameFocus {
                    TextField("", text: renameText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .focused(renameFocus)
                        .onSubmit { onRenameCommit() }
                        .onExitCommand { onRenameCancel() }
                        .onChange(of: renameFocus.wrappedValue) { newValue in
                            if !newValue {
                                onRenameCommit()
                            }
                        }
                } else {
                    Text(project.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let git = project.gitStatus {
                    HStack(spacing: 6) {
                        Text(git.branch)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(git.displayText)
                            .font(.system(size: 11))
                            .foregroundStyle(statusColor(git))
                    }
                } else {
                    Text("no repo")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected
            ? Color.accentColor.opacity(0.12)
            : Color.clear)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
            }
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch project.state {
        case .activeVisible:
            Circle().fill(.green)
        case .activeBackground:
            Circle()
                .stroke(.green, lineWidth: 1.5)
        case .inactive:
            Circle().fill(Color.secondary.opacity(0.5))
        }
    }

    private func statusColor(_ git: Project.GitStatus) -> Color {
        if !git.isDirty && git.ahead == 0 && git.behind == 0 {
            return .green
        }
        if git.isDirty { return .yellow }
        return .blue
    }
}
