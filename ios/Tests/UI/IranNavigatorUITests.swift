import XCTest

final class IranNavigatorUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testBundledWorldShellAndNorthCompassLaunch() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["کجا می‌رویم؟"].waitForExistence(timeout: 20))
        let north = app.buttons["برگشت نقشه به جهت شمال"]
        XCTAssertTrue(north.exists)
        north.tap()
        XCTAssertFalse(app.buttons["شروع حرکت"].exists, "Travel options appear only after selecting a destination")
    }
    func testBundledSearchDialogOpensAndCloses() {
        let app = XCUIApplication()
        app.launch()
        let search = app.buttons["کجا می‌رویم؟"]
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap()
        let close = app.buttons["بستن جست‌وجو"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(search.exists)
    }
}
