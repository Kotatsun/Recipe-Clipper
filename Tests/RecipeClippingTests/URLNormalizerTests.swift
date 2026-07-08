import XCTest
@testable import RecipeClipping

@MainActor
final class URLNormalizerTests: XCTestCase {
    func testDropsTrackingQueryParameters() {
        XCTAssertEqual(
            URLNormalizer.normalizedString(for: "https://example.com/recipe?utm_source=x&utm_medium=y&fbclid=abc&id=3"),
            "https://example.com/recipe?id=3"
        )
    }

    func testDropsQueryEntirelyWhenOnlyTrackingParameters() {
        XCTAssertEqual(
            URLNormalizer.normalizedString(for: "https://example.com/recipe?fbclid=abc&gclid=def"),
            "https://example.com/recipe"
        )
    }

    func testSortsQueryParameters() {
        XCTAssertEqual(
            URLNormalizer.normalizedString(for: "https://example.com/a?b=2&a=1"),
            "https://example.com/a?a=1&b=2"
        )
    }

    func testRemovesFragmentAndTrailingSlash() {
        XCTAssertEqual(
            URLNormalizer.normalizedString(for: "https://example.com/recipe/#steps"),
            "https://example.com/recipe"
        )
    }

    func testUpgradesHTTPToHTTPS() {
        XCTAssertEqual(
            URLNormalizer.normalizedString(for: "http://Example.com/a"),
            "https://example.com/a"
        )
    }

    func testNormalizesInstagramPostURL() {
        XCTAssertEqual(
            URLNormalizer.normalizedString(for: "https://www.instagram.com/reel/ABC123/?igsh=xyz&utm_source=ig"),
            "https://www.instagram.com/reel/ABC123/"
        )
    }

    func testTrackingVariantsNormalizeToSameString() {
        let a = URLNormalizer.normalizedString(for: "https://example.com/recipe/10?utm_source=share")
        let b = URLNormalizer.normalizedString(for: "https://example.com/recipe/10/")
        XCTAssertEqual(a, b)
    }

    func testFindsURLInsideSharedText() {
        XCTAssertEqual(
            URLNormalizer.normalizedURL(for: "これ見て https://example.com/r/1 作ろう")?.absoluteString,
            "https://example.com/r/1"
        )
    }

    func testAddsSchemeToBareDomain() {
        XCTAssertEqual(
            URLNormalizer.normalizedURL(for: "cookpad.com/recipe/123")?.absoluteString,
            "https://cookpad.com/recipe/123"
        )
    }

    func testRejectsNonURLText() {
        XCTAssertNil(URLNormalizer.normalizedURL(for: "こんにちは、今日の夕飯どうしよう"))
    }

    func testImportURLRoundTrip() throws {
        let shared = try XCTUnwrap(URL(string: "https://example.com/recipe?id=1"))
        let encoded = try XCTUnwrap(URLNormalizer.encodedImportURL(for: shared))
        XCTAssertEqual(URLNormalizer.importURLValue(from: encoded), shared.absoluteString)
    }
}
