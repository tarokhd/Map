import XCTest
@testable import IranNavigator

final class WorldHostPolicyTests: XCTestCase {
    func testBridgeOnlyAcceptsCurrentLoopbackOriginAndBundledPath() {
        let origin = URL(string: "http://127.0.0.1:12345")!
        XCTAssertTrue(WorldHostPolicy.trusted(URL(string: "http://127.0.0.1:12345/assets/world/index.html"), origin: origin))
        for url in ["http://127.0.0.1:54321/assets/world/index.html", "http://localhost:12345/assets/world/index.html", "http://example.com/assets/world/index.html", "http://user@127.0.0.1:12345/assets/world/index.html", "http://127.0.0.1:12345/other/index.html"] {
            XCTAssertFalse(WorldHostPolicy.trusted(URL(string: url), origin: origin))
        }
    }
    func testTraversalCannotEscapePackagedDirectory() {
        XCTAssertTrue(WorldHostPolicy.validAssetPath("/assets/world/vendor/maplibre-gl.js"))
        XCTAssertFalse(WorldHostPolicy.validAssetPath("/assets/world/../secret"))
        XCTAssertFalse(WorldHostPolicy.validAssetPath("/assets/world/..\\secret"))
    }
}
