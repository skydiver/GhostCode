import Foundation

/// Whether this build may check for updates, and which appcast it reads.
///
/// Only release builds from the GitHub workflow set `GhostCodeUpdatesEnabled`
/// to YES, so local and Debug builds never start Sparkle and can never replace
/// themselves with a release. The feed URL lives here rather than in
/// Info.plist because Ghostty's Info.plist is run through the C preprocessor,
/// where `//` starts a comment.
enum UpdateConfiguration: Equatable {
    case available(URL)
    case unconfigured

    /// Always redirects to the newest release's appcast.xml.
    static let feedURLString = "https://github.com/skydiver/GhostCode/releases/latest/download/appcast.xml"

    var feedURL: URL? {
        guard case .available(let url) = self else { return nil }
        return url
    }

    static func current(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> UpdateConfiguration {
        resolve(
            enabled: bundle.object(forInfoDictionaryKey: "GhostCodeUpdatesEnabled") as? String,
            publicKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            override: environment["GHOSTCODE_UPDATE_ENDPOINT"]
        )
    }

    static func resolve(enabled: String?, publicKey: String?, override: String?) -> UpdateConfiguration {
        guard enabled?.trimmingCharacters(in: .whitespaces) == "YES" else { return .unconfigured }
        guard let publicKey, !publicKey.trimmingCharacters(in: .whitespaces).isEmpty else { return .unconfigured }

        if let override, let url = httpsURL(override) {
            return .available(url)
        }
        guard let url = httpsURL(feedURLString) else { return .unconfigured }
        return .available(url)
    }

    private static func httpsURL(_ string: String) -> URL? {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespaces)),
              url.scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
