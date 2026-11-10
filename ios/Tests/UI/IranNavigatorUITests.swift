import CoreLocation
import XCTest

final class IranNavigatorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let simulatedLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 35.7006, longitude: 51.4050),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 90,
            speed: 8,
            timestamp: Date()
        )
        if #available(iOS 16.4, *) {
            XCUIDevice.shared.location = XCUILocation(location: simulatedLocation)
        }
    }

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

    func testCurrentLocationControlReceivesSimulatedGPS() {
        let app = XCUIApplication()
        app.launch()

        let locateButton = app.buttons["رفتن به موقعیت فعلی"]
        XCTAssertTrue(locateButton.waitForExistence(timeout: 20))
        locateButton.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Allow")
        ).firstMatch
        if allowButton.waitForExistence(timeout: 3) {
            allowButton.tap()
        }

        let gpsAccuracy = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "دقت GPS")
        ).firstMatch
        XCTAssertTrue(gpsAccuracy.waitForExistence(timeout: 15))
    }
}
