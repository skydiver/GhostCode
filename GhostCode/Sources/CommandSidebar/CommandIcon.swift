import SwiftUI
import AppKit

/// Decodes and caches `NSImage` instances from base64-encoded SVG data URIs.
/// Strings that don't match the expected prefix (or fail to decode) return nil,
/// allowing callers to fall back to an alternate rendering path.
///
/// Icons come from the user's commands file and are looked up on every render,
/// so the cache is bounded, oversized input is rejected, and failures are cached too.
@MainActor
final class SVGIconCache {
    static let shared = SVGIconCache()

    /// Longest data URI payload decoded; larger icons fall back to the SF Symbol path.
    static let maxEncodedLength = 256 * 1024
    private static let prefix = "data:image/svg+xml;base64,"

    /// NSCache needs a class value; `image == nil` records a failed decode.
    private final class Entry {
        let image: NSImage?
        init(_ image: NSImage?) { self.image = image }
    }

    private let cache = NSCache<NSString, Entry>()
    private let decode: (Data) -> NSImage?

    init(decode: @escaping (Data) -> NSImage? = { NSImage(data: $0) }) {
        self.decode = decode
        cache.countLimit = 200
    }

    /// Returns a template-rendered `NSImage` for a base64 SVG data URI.
    /// Returns nil for strings that aren't data URIs or that fail to decode.
    func image(for icon: String) -> NSImage? {
        guard icon.hasPrefix(Self.prefix) else { return nil }
        if let entry = cache.object(forKey: icon as NSString) { return entry.image }

        let base64 = icon.dropFirst(Self.prefix.count)
        var image: NSImage?
        if base64.utf8.count <= Self.maxEncodedLength,
           let data = Data(base64Encoded: String(base64)),
           let decoded = decode(data) {
            decoded.isTemplate = true
            image = decoded
        }
        cache.setObject(Entry(image), forKey: icon as NSString)
        return image
    }
}

/// Renders a command palette icon — either a base64 SVG data URI or an SF Symbol name.
/// Detection happens by prefix; SF Symbol is the fallback path.
struct CommandIcon: View {
    let name: String
    let size: CGFloat
    var weight: Font.Weight = .regular

    var body: some View {
        if let image = SVGIconCache.shared.image(for: name) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: name)
                .font(.system(size: size, weight: weight))
        }
    }
}
