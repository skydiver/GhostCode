import SwiftUI

/// The branded splash screen shown when no terminal is active.
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
