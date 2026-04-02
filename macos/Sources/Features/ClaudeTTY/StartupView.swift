import SwiftUI

/// The branded splash screen shown when no project is selected.
struct StartupView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text(asciiLogo)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
                .multilineTextAlignment(.center)

            Text("ClaudeTTY")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.secondary.opacity(0.8))

            Text("Select a project to get started")
                .font(.system(size: 13))
                .foregroundColor(.secondary.opacity(0.5))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var asciiLogo: String {
        """
         ██████╗██╗      █████╗ ██╗   ██╗██████╗ ███████╗
        ██╔════╝██║     ██╔══██╗██║   ██║██╔══██╗██╔════╝
        ██║     ██║     ███████║██║   ██║██║  ██║█████╗
        ██║     ██║     ██╔══██║██║   ██║██║  ██║██╔══╝
        ╚██████╗███████╗██║  ██║╚██████╔╝██████╔╝███████╗
         ╚═════╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝
        """
    }
}

/// Landing page shown when a project is selected but no session is running.
struct ProjectLandingView: View {
    let projectName: String
    let onStartSession: () -> Void
    let onResumeSession: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "folder.fill")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.3))

            Text(projectName)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.primary.opacity(0.8))

            HStack(spacing: 10) {
                LandingButton(
                    title: "New Session",
                    icon: "play.fill",
                    style: .primary,
                    action: onStartSession
                )

                LandingButton(
                    title: "Resume Last Session",
                    icon: "arrow.counterclockwise",
                    style: .secondary,
                    action: onResumeSession
                )
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
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
            .frame(width: 200)
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
