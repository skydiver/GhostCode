import SwiftUI

/// The branded splash screen shown when no project is selected.
struct StartupView: View {
    private let asciiLogo: String

    init() {
        asciiLogo = Self.loadRandomLogo()
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text(asciiLogo)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.6))
                .multilineTextAlignment(.leading)

            Divider()
                .frame(width: 200)
                .opacity(0.4)

            Text("Select a project to get started")
                .font(.system(size: 13))
                .foregroundStyle(.secondary.opacity(0.5))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private static func loadRandomLogo() -> String {
        guard let logosURL = Bundle.main.url(forResource: "AsciiLogos", withExtension: nil),
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: logosURL, includingPropertiesForKeys: nil),
              !contents.isEmpty
        else {
            return "GhostCode"
        }

        let asciiFiles = contents.filter { $0.pathExtension == "ascii" }
        guard let chosen = asciiFiles.randomElement(),
              let data = try? String(contentsOf: chosen, encoding: .utf8)
        else {
            return "GhostCode"
        }

        return data.trimmingCharacters(in: .newlines)
    }
}

/// An entry in the landing page picker: an AI binary, or a plain shell.
private enum LandingChoice: Hashable {
    case binary(SupportedBinary)
    case shell

    var binary: SupportedBinary? {
        guard case .binary(let binary) = self else { return nil }
        return binary
    }

    var supportsSessionInfo: Bool {
        binary?.supportsSessionInfo ?? false
    }
}

/// Landing page shown when a project is selected but no session is running.
struct ProjectLandingView: View {
    let project: Project
    let globalDefaultBinary: SupportedBinary
    let onStartSession: () -> Void
    let onResumeSession: () -> Void
    let onOpenShell: () -> Void
    let onBinaryChanged: (SupportedBinary) -> Void

    @State private var selectedChoice: LandingChoice
    @State private var sessionInfo = SessionInfoProvider.SessionInfo(count: 0, lastDate: nil)

    init(
        project: Project,
        globalDefaultBinary: SupportedBinary,
        onStartSession: @escaping () -> Void,
        onResumeSession: @escaping () -> Void,
        onOpenShell: @escaping () -> Void,
        onBinaryChanged: @escaping (SupportedBinary) -> Void
    ) {
        self.project = project
        self.globalDefaultBinary = globalDefaultBinary
        self.onStartSession = onStartSession
        self.onResumeSession = onResumeSession
        self.onOpenShell = onOpenShell
        self.onBinaryChanged = onBinaryChanged
        self._selectedChoice = State(initialValue: .binary(project.binary ?? globalDefaultBinary))
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "folder.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.3))

            Text(project.name)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.primary.opacity(0.8))

            Picker(selection: $selectedChoice) {
                ForEach(SupportedBinary.allCases) { binary in
                    Text(binary.displayName).tag(LandingChoice.binary(binary))
                }
                Text("Shell").tag(LandingChoice.shell)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .frame(width: 420)
            .onChange(of: selectedChoice) { newValue in
                guard let binary = newValue.binary else { return }
                onBinaryChanged(binary)
            }

            VStack(spacing: 16) {
                ProjectInfoSection(
                    project: project,
                    sessionInfo: sessionInfo,
                    showSessionInfo: selectedChoice.supportsSessionInfo
                )

                HStack(spacing: 10) {
                    if let binary = selectedChoice.binary {
                        LandingButton(
                            title: "New Session",
                            icon: "play.fill",
                            style: .primary,
                            action: onStartSession
                        )

                        if binary.resumeArg != nil && sessionInfo.count > 0 {
                            LandingButton(
                                title: "Resume Last Session",
                                icon: "arrow.counterclockwise",
                                style: .secondary,
                                action: onResumeSession
                            )
                        }
                    } else {
                        LandingButton(
                            title: "Open Shell",
                            icon: "terminal",
                            style: .primary,
                            action: onOpenShell
                        )
                    }
                }
            }
            .frame(width: 420)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: selectedChoice) {
            if selectedChoice.supportsSessionInfo {
                sessionInfo = await SessionInfoProvider.info(for: project.path)
            } else {
                sessionInfo = SessionInfoProvider.SessionInfo(count: 0, lastDate: nil)
            }
        }
    }
}

// MARK: - Project Info

private struct ProjectInfoSection: View {
    let project: Project
    let sessionInfo: SessionInfoProvider.SessionInfo
    let showSessionInfo: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InfoRow(icon: "folder", text: displayPath)
            InfoRow(icon: "arrow.triangle.branch", text: gitText)
            if showSessionInfo {
                InfoRow(icon: "text.bubble", text: sessionInfo.summary(relativeTo: Date()))
            } else {
                InfoRow(icon: "text.bubble", text: " ")
                    .opacity(0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.03))
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var displayPath: String {
        ProjectPathFormatter.abbreviatingHome(
            project.path,
            home: FileManager.default.homeDirectoryForCurrentUser.path
        )
    }

    private var gitText: String {
        guard let git = project.gitStatus else { return "no repo" }
        return "\(git.branch) · \(git.displayText)"
    }

}

private struct InfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.6))
                .frame(width: 16, alignment: .center)

            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Session Info Provider

enum ProjectPathFormatter {
    /// Replaces a leading home directory with `~`. Siblings such as
    /// `/Users/martinez` for home `/Users/martin` are left alone.
    static func abbreviatingHome(_ path: String, home: String) -> String {
        if path == home { return "~" }
        guard path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

enum SessionInfoProvider {
    /// Claude Code caps directory names at this length and appends a hash beyond it.
    private static let maxDirectoryNameLength = 200

    /// The directory name Claude Code uses under `~/.claude/projects` for a project:
    /// every UTF-16 unit that isn't an ASCII letter or digit becomes `-`.
    /// (Matches Claude Code 2.1.x; names over 200 characters also get a hash suffix.)
    static func directoryName(for projectPath: String) -> String {
        let units = projectPath.utf16.map { unit -> Character in
            guard let scalar = Unicode.Scalar(unit), scalar.isASCII,
                  scalar.properties.isAlphabetic || ("0"..."9").contains(scalar)
            else { return "-" }
            return Character(scalar)
        }
        return String(units)
    }

    /// Finds the project's sessions directory in `root`. Long names end in a hash
    /// GhostCode can't reproduce, so those are matched by their truncated prefix.
    static func sessionsDirectory(for projectPath: String, in root: String) -> String? {
        let name = directoryName(for: projectPath)
        let fm = FileManager.default
        if name.count <= maxDirectoryNameLength {
            let path = "\(root)/\(name)"
            return fm.fileExists(atPath: path) ? path : nil
        }
        let prefix = String(name.prefix(maxDirectoryNameLength)) + "-"
        guard let match = (try? fm.contentsOfDirectory(atPath: root))?.first(where: { $0.hasPrefix(prefix) })
        else { return nil }
        return "\(root)/\(match)"
    }

    struct SessionInfo {
        let count: Int
        let lastDate: Date?

        /// e.g. "3 sessions · last 2 hours ago". The date is omitted when no
        /// session file could be stat'ed (files rotated between listing and stat).
        func summary(relativeTo now: Date) -> String {
            guard count > 0 else { return "No previous sessions" }
            let sessions = "\(count) \(count == 1 ? "session" : "sessions")"
            guard let lastDate else { return sessions }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "\(sessions) · last \(formatter.localizedString(for: lastDate, relativeTo: now))"
        }
    }

    static func info(for projectPath: String) async -> SessionInfo {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let fm = FileManager.default
                guard let sessionsDir = sessionsDirectory(for: projectPath, in: "\(home)/.claude/projects"),
                      let contents = try? fm.contentsOfDirectory(atPath: sessionsDir) else {
                    continuation.resume(returning: SessionInfo(count: 0, lastDate: nil))
                    return
                }

                let jsonlFiles = contents.filter { $0.hasSuffix(".jsonl") }
                guard !jsonlFiles.isEmpty else {
                    continuation.resume(returning: SessionInfo(count: 0, lastDate: nil))
                    return
                }

                var latestDate: Date?
                for file in jsonlFiles {
                    let fullPath = "\(sessionsDir)/\(file)"
                    if let attrs = try? fm.attributesOfItem(atPath: fullPath),
                       let modified = attrs[.modificationDate] as? Date {
                        if latestDate.map({ modified > $0 }) ?? true {
                            latestDate = modified
                        }
                    }
                }

                continuation.resume(returning: SessionInfo(count: jsonlFiles.count, lastDate: latestDate))
            }
        }
    }
}

private struct LandingButton: View {
    let title: String
    let icon: String
    let style: Style
    let action: () -> Void

    @State private var isHovered = false

    enum Style {
        case primary, secondary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(style == .primary ? .white : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(style == .primary
                ? Color.accentColor
                : Color.primary.opacity(isHovered ? 0.08 : 0.05))
            .clipShape(.rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(style == .primary
                        ? Color.clear
                        : Color.primary.opacity(isHovered ? 0.2 : 0.1),
                    lineWidth: 1)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
