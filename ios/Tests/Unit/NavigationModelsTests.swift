import XCTest
@testable import IranNavigator

final class NavigationModelsTests: XCTestCase {
    func testTravelModesUseSharedValhallaCostings() {
        XCTAssertEqual(TravelMode.car.costingCandidates, ["auto"])
        XCTAssertEqual(TravelMode.motorcycle.costingCandidates, ["motorcycle", "motor_scooter"])
        XCTAssertEqual(TravelMode.walking.costingCandidates, ["pedestrian"])
    }

    func testValhallaStartRightAndLeftInstructionsAreDistinct() {
        XCTAssertEqual(
            PersianInstructionFormatter.instruction(type: 2, streetName: ""),
            "از سمت راست حرکت را آغاز کنید"
        )
        XCTAssertEqual(
            PersianInstructionFormatter.instruction(type: 3, streetName: ""),
            "از سمت چپ حرکت را آغاز کنید"
        )
    }

    func testValhallaMergeAndStayStraightInstructions() {
        XCTAssertEqual(
            PersianInstructionFormatter.instruction(type: 22, streetName: ""),
            "به مسیر مستقیم ادامه دهید"
        )
        XCTAssertEqual(
            PersianInstructionFormatter.instruction(type: 37, streetName: ""),
            "از سمت راست به مسیر اصلی ادغام شوید"
        )
        XCTAssertEqual(
            PersianInstructionFormatter.instruction(type: 38, streetName: ""),
            "از سمت چپ به مسیر اصلی ادغام شوید"
        )
    }

    func testStreetNameIsIncludedInTurnInstruction() {
        XCTAssertEqual(
            PersianInstructionFormatter.instruction(type: 10, streetName: "ولیعصر"),
            "به راست بپیچید و وارد ولیعصر شوید"
        )
    }

    func testDistanceFormattingUsesRoundedPersianDigits() {
        XCTAssertEqual(PersianInstructionFormatter.distance(1_500), "۱٫۵ کیلومتر")
        XCTAssertEqual(PersianInstructionFormatter.distance(25.6), "۲۶ متر")
    }

    func testLocationFreshnessAndAccuracyBoundaries() {
        let now = Date()
        XCTAssertTrue(
            NavigationLocationQuality.isUsable(
                horizontalAccuracy: 12,
                timestamp: now.addingTimeInterval(-8),
                now: now
            )
        )
        XCTAssertFalse(
            NavigationLocationQuality.isUsable(
                horizontalAccuracy: 12,
                timestamp: now.addingTimeInterval(-40),
                now: now
            )
        )
        XCTAssertFalse(
            NavigationLocationQuality.isUsable(
                horizontalAccuracy: 120,
                timestamp: now,
                now: now
            )
        )
        XCTAssertFalse(
            NavigationLocationQuality.isUsable(
                horizontalAccuracy: -1,
                timestamp: now,
                now: now
            )
        )
    }

    func testPolyline6DecoderRoundTripsTehranCoordinates() {
        let source = [
            RouteCoordinate(latitude: 35.7006, longitude: 51.4050),
            RouteCoordinate(latitude: 35.7219, longitude: 51.3347),
            RouteCoordinate(latitude: 35.7350, longitude: 51.3100)
        ]

        let encoded = encodePolyline6(source)
        let decoded = Polyline6Decoder.decode(encoded)

        XCTAssertEqual(decoded.count, source.count)
        for (actual, expected) in zip(decoded, source) {
            XCTAssertEqual(actual.latitude, expected.latitude, accuracy: 0.000001)
            XCTAssertEqual(actual.longitude, expected.longitude, accuracy: 0.000001)
        }
    }

    func testPolyline6DecoderRejectsMalformedGeometry() {
        XCTAssertTrue(Polyline6Decoder.decode("!").isEmpty)
    }

    private func encodePolyline6(_ points: [RouteCoordinate]) -> String {
        var output = ""
        var previousLatitude = 0
        var previousLongitude = 0

        func encodeDelta(_ delta: Int) -> String {
            var value = delta < 0 ? ~(delta << 1) : (delta << 1)
            var encoded = ""
            while value >= 0x20 {
                let next = (0x20 | (value & 0x1f)) + 63
                encoded.append(Character(UnicodeScalar(next)!))
                value >>= 5
            }
            encoded.append(Character(UnicodeScalar(value + 63)!))
            return encoded
        }

        for point in points {
            let latitude = Int((point.latitude * 1_000_000).rounded())
            let longitude = Int((point.longitude * 1_000_000).rounded())
            output += encodeDelta(latitude - previousLatitude)
            output += encodeDelta(longitude - previousLongitude)
            previousLatitude = latitude
            previousLongitude = longitude
        }
        return output
    }
}
