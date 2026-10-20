import XCTest
@testable import TeroCore
final class ShoppingTests: XCTestCase {
    func testJevRoutesOnlyClearProductRecommendations() {
        func scores(_ shop: Double, _ explain: Double) -> [SemanticScore] {
            [.init(id: "shop", score: shop, confidence: 0.9), .init(id: "explain", score: explain, confidence: 0.9)]
        }
        XCTAssertTrue(ShoppingRequest.shouldShowProducts(scores(2.8, 0.4)))
        XCTAssertFalse(ShoppingRequest.shouldShowProducts(scores(0.2, 2.9)))
        XCTAssertFalse(ShoppingRequest.shouldShowProducts(scores(1.8, 0.4)))
        XCTAssertFalse(ShoppingRequest.shouldShowProducts(scores(2.5, 2.5)))
        XCTAssertFalse(ShoppingRequest.shouldShowProducts([]))
        XCTAssertFalse(ShoppingRequest.shouldShowProducts([.init(id: "shop", score: 3, confidence: 1)]))
        XCTAssertFalse(ShoppingRequest.shouldShowProducts(scores(.nan, 0)))
        XCTAssertFalse(ShoppingRequest.shouldShowProducts(scores(4, 0)))
        XCTAssertFalse(ShoppingRequest.shouldShowProducts([
            .init(id: "shop", score: 3, confidence: 1, probabilities: ["0": 1]),
            .init(id: "explain", score: 0, confidence: 1)]))
    }
    func testOptionalPreferencesAndBoundedRequests() {
        XCTAssertNotNil(ShoppingRequest.input(request: "A keyboard", preferences: ""))
        XCTAssertNil(ShoppingRequest.input(request: "", preferences: ""))
        XCTAssertNil(ShoppingRequest.input(request: "Keyboard", preferences: String(repeating: "a", count: 601)))
    }
    func testRejectsNonPublicAndNonHTTPSProductURLs() {
        for url in ["http://example.com/product", "https://localhost/product", "https://127.0.0.1/product", "https://user:pass@example.com", "file:///tmp/product", "https://host.local/product"] {
            XCTAssertNil(ShoppingRequest.publicURL(url), url)
        }
        XCTAssertNotNil(ShoppingRequest.publicURL("https://example.com/product?q=keyboard"))
    }
}
