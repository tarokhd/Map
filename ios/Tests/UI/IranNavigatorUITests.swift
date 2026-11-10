import XCTest

final class IranNavigatorUITests: XCTestCase {
    func testMainNavigationInterfaceLaunches() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["مسیریابی"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["رفتن به موقعیت فعلی"].exists)
        XCTAssertTrue(app.buttons["تغییر به نقشه دوبعدی"].exists)
    }

    func testThreeDimensionalMapControlToggles() {
        let app = XCUIApplication()
        app.launch()

        let toTwoD = app.buttons["تغییر به نقشه دوبعدی"]
        XCTAssertTrue(toTwoD.waitForExistence(timeout: 20))
        toTwoD.tap()

        XCTAssertTrue(app.buttons["تغییر به نقشه سه‌بعدی"].waitForExistence(timeout: 5))
    }

    func testCurrentLocationControlRequestsLocationWithoutCrashing() {
        let app = XCUIApplication()
        app.launch()

        let locateButton = app.buttons["رفتن به موقعیت فعلی"]
        XCTAssertTrue(locateButton.waitForExistence(timeout: 20))
        locateButton.tap()

        let status = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "موقعیت")
        ).firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))
    }
}
