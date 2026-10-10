import XCTest
@testable import Ghostty

final class UpdateConfigurationTests: XCTestCase {

    private let pubkey = "P6Wn+oJ3kM4Q0Yy8b1c2d3e4f5g6h7i8j9k0l1m2n3o="
    private let feed = URL(string: UpdateConfiguration.feedURLString)!

    func testEnabledBuildUsesTheGitHubFeed() {
        XCTAssertEqual(
            UpdateConfiguration.resolve(enabled: "YES", publicKey: pubkey, override: nil),
            .available(feed)
        )
    }

    func testFeedURLIsTheLatestReleaseAppcast() {
        XCTAssertEqual(
            UpdateConfiguration.feedURLString,
            "https://github.com/skydiver/GhostCode/releases/latest/download/appcast.xml"
        )
    }

    /// Local builds never set GHOSTCODE_UPDATES_ENABLED, so the key expands to "".
    func testDisabledBuildIsUnconfigured() {
        XCTAssertEqual(UpdateConfiguration.resolve(enabled: "", publicKey: pubkey, override: nil), .unconfigured)
        XCTAssertEqual(UpdateConfiguration.resolve(enabled: nil, publicKey: pubkey, override: nil), .unconfigured)
        XCTAssertEqual(UpdateConfiguration.resolve(enabled: "NO", publicKey: pubkey, override: nil), .unconfigured)
    }

    /// Without the public key nothing could verify a download.
    func testMissingPublicKeyIsUnconfigured() {
        XCTAssertEqual(UpdateConfiguration.resolve(enabled: "YES", publicKey: "", override: nil), .unconfigured)
        XCTAssertEqual(UpdateConfiguration.resolve(enabled: "YES", publicKey: nil, override: nil), .unconfigured)
        XCTAssertEqual(UpdateConfiguration.resolve(enabled: "YES", publicKey: "   ", override: nil), .unconfigured)
    }

    func testHTTPSOverrideWins() {
        XCTAssertEqual(
            UpdateConfiguration.resolve(enabled: "YES", publicKey: pubkey, override: "https://example.com/staging.xml"),
            .available(URL(string: "https://example.com/staging.xml")!)
        )
    }

    /// An unusable override falls back to the shipped feed instead of disabling updates.
    func testUnusableOverrideFallsBackToTheFeed() {
        for override in ["http://example.com/staging.xml", "not a url", "https://", ""] {
            XCTAssertEqual(
                UpdateConfiguration.resolve(enabled: "YES", publicKey: pubkey, override: override),
                .available(feed),
                "override: \(override)"
            )
        }
    }

    /// The override never turns updates on in a build that has them off.
    func testOverrideDoesNotEnableADisabledBuild() {
        XCTAssertEqual(
            UpdateConfiguration.resolve(enabled: "", publicKey: pubkey, override: "https://example.com/staging.xml"),
            .unconfigured
        )
    }

    func testFeedURLAccessor() {
        XCTAssertEqual(UpdateConfiguration.available(feed).feedURL, feed)
        XCTAssertNil(UpdateConfiguration.unconfigured.feedURL)
    }
}
