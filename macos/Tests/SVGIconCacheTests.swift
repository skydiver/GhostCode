import XCTest
@testable import Ghostty

final class SVGIconCacheTests: XCTestCase {
    private let sampleSVG =
        #"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10"/></svg>"#

    private var validDataURI: String {
        let base64 = Data(sampleSVG.utf8).base64EncodedString()
        return "data:image/svg+xml;base64,\(base64)"
    }

    func testReturnsNilForSFSymbolName() {
        let cache = SVGIconCache()
        XCTAssertNil(cache.image(for: "hammer.fill"))
    }

    func testReturnsNilForUnrelatedString() {
        let cache = SVGIconCache()
        XCTAssertNil(cache.image(for: "not even close"))
    }

    func testReturnsNilForEmptyString() {
        let cache = SVGIconCache()
        XCTAssertNil(cache.image(for: ""))
    }

    func testReturnsNilForInvalidBase64() {
        let cache = SVGIconCache()
        XCTAssertNil(cache.image(for: "data:image/svg+xml;base64,!!!not-base64!!!"))
    }

    func testReturnsNilForBase64ThatIsNotAnImage() {
        let bytes = Data("definitely not svg or any image".utf8).base64EncodedString()
        let cache = SVGIconCache()
        XCTAssertNil(cache.image(for: "data:image/svg+xml;base64,\(bytes)"))
    }

    func testDecodesValidBase64SVGToNSImage() {
        let cache = SVGIconCache()
        let image = cache.image(for: validDataURI)
        XCTAssertNotNil(image, "Valid base64 SVG should decode to an NSImage")
        XCTAssertTrue(image?.isTemplate ?? false,
                      "Decoded image should be marked as a template for monochrome tinting")
    }

    func testCachesDecodedImageInstance() {
        let cache = SVGIconCache()
        let first = cache.image(for: validDataURI)
        let second = cache.image(for: validDataURI)
        XCTAssertNotNil(first)
        XCTAssertTrue(first === second,
                      "Repeated lookups for the same icon string should return the same NSImage")
    }
}
