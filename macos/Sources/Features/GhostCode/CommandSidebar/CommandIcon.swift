import SwiftUI
import AppKit

/// Decodes and caches `NSImage` instances from base64-encoded SVG data URIs.
/// Strings that don't match the expected prefix (or fail to decode) return nil,
/// allowing callers to fall back to an alternate rendering path.
final class SVGIconCache {
    static let shared = SVGIconCache()

    private static let prefix = "data:image/svg+xml;base64,"
    private var cache: [String: NSImage] = [:]

    /// Returns a template-rendered `NSImage` for a base64 SVG data URI.
    /// Returns nil for strings that aren't data URIs or that fail to decode.
    func image(for icon: String) -> NSImage? {
        if let cached = cache[icon] { return cached }
        guard icon.hasPrefix(Self.prefix) else { return nil }
        let base64 = String(icon.dropFirst(Self.prefix.count))
        guard let data = Data(base64Encoded: base64),
              let image = NSImage(data: data) else { return nil }
        image.isTemplate = true
        cache[icon] = image
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
