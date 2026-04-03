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
                .foregroundColor(.secondary.opacity(0.6))
                .multilineTextAlignment(.leading)

            Divider()
                .frame(width: 200)
                .opacity(0.4)

            Text("Select a project to get started")
                .font(.system(size: 13))
                .foregroundColor(.secondary.opacity(0.5))

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

/// Landing page shown when a project is selected but no session is running.
struct ProjectLandingView: View {
    let project: Project
    let globalDefaultBinary: SupportedBinary
    let onStartSession: () -> Void
    let onResumeSession: () -> Void
    let onBinaryChanged: (SupportedBinary) -> Void

    @State private var selectedBinary: SupportedBinary
    @State private var sessionInfo = SessionInfoProvider.SessionInfo(count: 0, lastDate: nil)

    init(
        project: Project,
        globalDefaultBinary: SupportedBinary,
        onStartSession: @escaping () -> Void,
        onResumeSession: @escaping () -> Void,
        onBinaryChanged: @escaping (SupportedBinary) -> Void
    ) {
        self.project = project
        self.globalDefaultBinary = globalDefaultBinary
        self.onStartSession = onStartSession
        self.onResumeSession = onResumeSession
        self.onBinaryChanged = onBinaryChanged
        self._selectedBinary = State(initialValue: project.binary ?? globalDefaultBinary)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "folder.fill")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.3))

            Text(project.name)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.primary.opacity(0.8))

            VStack(spacing: 16) {
                ProjectInfoSection(
                    project: project,
                    sessionInfo: sessionInfo,
                    showSessionInfo: selectedBinary.supportsSessionInfo
                )

                Picker("CLI", selection: $selectedBinary) {
                    ForEach(SupportedBinary.allCases) { binary in
                        Text(binary.displayName).tag(binary)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedBinary) { newValue in
                    onBinaryChanged(newValue)
                }

                HStack(spacing: 10) {
                    LandingButton(
                        title: "New Session",
                        icon: "play.fill",
                        style: .primary,
                        action: onStartSession
                    )

                    if selectedBinary.resumeArg != nil && sessionInfo.count > 0 {
                        LandingButton(
                            title: "Resume Last Session",
                            icon: "arrow.counterclockwise",
                            style: .secondary,
                            action: onResumeSession
                        )
                    }
                }
            }
            .frame(width: 420)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: selectedBinary) {
            if selectedBinary.supportsSessionInfo {
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
                InfoRow(icon: "text.bubble", text: sessionText(sessionInfo))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if project.path.hasPrefix(home) {
            return "~" + project.path.dropFirst(home.count)
        }
        return project.path
    }

    private var gitText: String {
        guard let git = project.gitStatus else { return "no repo" }
        return "\(git.branch) · \(git.displayText)"
    }

    private func sessionText(_ info: SessionInfoProvider.SessionInfo) -> String {
        guard info.count > 0 else { return "No previous sessions" }
        let sessionWord = info.count == 1 ? "session" : "sessions"
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: info.lastDate!, relativeTo: Date())
        return "\(info.count) \(sessionWord) · last \(relative)"
    }
}

private struct InfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: 16, alignment: .center)

            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Session Info Provider

enum SessionInfoProvider {
    struct SessionInfo {
        let count: Int
        let lastDate: Date?
    }

    static func info(for projectPath: String) async -> SessionInfo {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let encoded = projectPath.replacingOccurrences(of: "/", with: "-")
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let sessionsDir = "\(home)/.claude/projects/\(encoded)"

                let fm = FileManager.default
                guard let contents = try? fm.contentsOfDirectory(atPath: sessionsDir) else {
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
                        if latestDate == nil || modified > latestDate! {
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
            .foregroundColor(style == .primary ? .white : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(style == .primary
                ? Color.accentColor
                : Color.primary.opacity(isHovered ? 0.08 : 0.05))
            .cornerRadius(8)
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
