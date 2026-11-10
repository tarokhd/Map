import CoreLocation
import Foundation

enum TravelMode: String, CaseIterable, Identifiable, Equatable {
    case car
    case motorcycle
    case walking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .car: return "خودرو"
        case .motorcycle: return "موتور"
        case .walking: return "پیاده"
        }
    }

    var valhallaCosting: String {
        switch self {
        case .car: return "auto"
        case .motorcycle: return "motorcycle"
        case .walking: return "pedestrian"
        }
    }

    var costingCandidates: [String] {
        self == .motorcycle ? ["motorcycle", "motor_scooter"] : [valhallaCosting]
    }
}

enum MapTheme: String, CaseIterable, Equatable {
    case dark
    case light

    var styleURL: URL {
        URL(string: self == .dark
            ? "https://tiles.openfreemap.org/styles/dark"
            : "https://tiles.openfreemap.org/styles/positron")!
    }
}

enum PointSelectionTarget: Equatable {
    case origin
    case destination
}

struct RouteCoordinate: Equatable, Hashable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

struct RouteManeuver: Identifiable {
    let id: Int
    let type: Int
    let instruction: String
    let streetName: String
    let lengthKilometers: Double
    let timeSeconds: Double
    let endShapeIndex: Int
}

struct NavigationRoute {
    let points: [RouteCoordinate]
    let maneuvers: [RouteManeuver]
    let distanceKilometers: Double
    let durationSeconds: Double
    let usedMotorcycleFallback: Bool

    init(
        points: [RouteCoordinate],
        maneuvers: [RouteManeuver],
        distanceKilometers: Double,
        durationSeconds: Double,
        usedMotorcycleFallback: Bool = false
    ) {
        self.points = points
        self.maneuvers = maneuvers
        self.distanceKilometers = distanceKilometers
        self.durationSeconds = durationSeconds
        self.usedMotorcycleFallback = usedMotorcycleFallback
    }
}

struct PlaceSearchResult: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let coordinate: RouteCoordinate

    var displayName: String {
        subtitle.isEmpty ? title : "\(title)، \(subtitle)"
    }
}

enum PersianInstructionFormatter {
    static func instruction(type: Int, streetName: String) -> String {
        let street = streetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasStreet = !street.isEmpty && street.lowercased() != "unnamed road"

        if type == 7, hasStreet {
            return "مسیر به (street) تبدیل می‌شود"
        }

        let action: String
        switch type {
        case 0: action = "به مسیر ادامه دهید"
        case 1: action = "حرکت را آغاز کنید"
        case 2: action = "از سمت راست حرکت را آغاز کنید"
        case 3: action = "از سمت چپ حرکت را آغاز کنید"
        case 4: action = "به مقصد رسیده‌اید"
        case 5: action = "از سمت راست به مقصد می‌رسید"
        case 6: action = "از سمت چپ به مقصد می‌رسید"
        case 7, 8: action = "به مسیر مستقیم ادامه دهید"
        case 9: action = "کمی به سمت راست متمایل شوید"
        case 10: action = "به راست بپیچید"
        case 11: action = "با زاویه تند به راست بپیچید"
        case 12, 13: action = "دور بزنید و در جهت مخالف حرکت کنید"
        case 14: action = "با زاویه تند به چپ بپیچید"
        case 15: action = "به چپ بپیچید"
        case 16: action = "کمی به سمت چپ متمایل شوید"
        case 17: action = "از مسیر مستقیم وارد رمپ شوید"
        case 18: action = "از رمپ سمت راست وارد شوید"
        case 19: action = "از رمپ سمت چپ وارد شوید"
        case 20: action = "خروجی سمت راست را انتخاب کنید"
        case 21: action = "خروجی سمت چپ را انتخاب کنید"
        case 22: action = "به مسیر مستقیم ادامه دهید"
        case 23: action = "در سمت راست مسیر بمانید"
        case 24: action = "در سمت چپ مسیر بمانید"
        case 25: action = "به مسیر ادغام شوید"
        case 26: action = "وارد میدان شوید"
        case 27: action = "از میدان خارج شوید"
        case 28: action = "وارد مسیر کشتی شوید"
        case 29: action = "از مسیر کشتی خارج شوید"
        case 30: action = "وارد مسیر حمل‌ونقل عمومی شوید"
        case 31: action = "وسیله یا خط حمل‌ونقل را عوض کنید"
        case 32: action = "در همین وسیله بمانید"
        case 33: action = "به مسیر اتصال حمل‌ونقل عمومی بروید"
        case 34: action = "در مسیر اتصال، وسیله را عوض کنید"
        case 35, 36: action = "به مقصد حمل‌ونقل عمومی رسیده‌اید"
        case 37: action = "از سمت راست به مسیر اصلی ادغام شوید"
        case 38: action = "از سمت چپ به مسیر اصلی ادغام شوید"
        case 39: action = "وارد آسانسور شوید"
        case 40: action = "از پله‌ها استفاده کنید"
        case 41: action = "از پله‌برقی استفاده کنید"
        case 42: action = "وارد ساختمان شوید"
        case 43: action = "از ساختمان خارج شوید"
        case 44: action = "به طبقه یا تراز دیگری بروید"
        case 45: action = "وسیله نقلیه را پارک کنید"
        default: action = "به مسیر ادامه دهید"
        }

        guard hasStreet, ![4, 5, 6, 28, 29, 30, 31, 32, 33, 34, 35, 36, 39, 40, 41, 42, 43, 44, 45].contains(type) else {
            return action
        }
        return "(action) و وارد (street) شوید"
    }

    static func distance(_ meters: Double) -> String {
        let safe = max(0, meters)
        if safe >= 1_000 {
            let kilometers = safe / 1_000
            let value = kilometers < 10
                ? String(format: "%.1f", kilometers)
                : String(Int(kilometers.rounded()))
            return "(persianDigits(value)) کیلومتر"
        }
        return "(persianDigits(String(Int(safe.rounded()))) ) متر"
    }

    static func duration(_ seconds: Double) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 {
            return "(persianDigits(String(hours))) ساعت و (persianDigits(String(remainder))) دقیقه"
        }
        return "(persianDigits(String(minutes))) دقیقه"
    }

    static func persianDigits(_ value: String) -> String {
        let digits = ["۰", "۱", "۲", "۳", "۴", "۵", "۶", "۷", "۸", "۹"]
        return value.map { character in
            if let number = character.wholeNumberValue, number >= 0, number <= 9 {
                return digits[number]
            }
            return character == "." ? "٫" : String(character)
        }.joined()
    }
}

enum NavigationLocationQuality {
    static func isFresh(
        timestamp: Date,
        now: Date = Date(),
        maximumAge: TimeInterval = 20
    ) -> Bool {
        let age = now.timeIntervalSince(timestamp)
        return age >= -2 && age <= maximumAge
    }

    static func isUsable(
        horizontalAccuracy: CLLocationAccuracy,
        timestamp: Date,
        now: Date = Date(),
        maximumAccuracy: CLLocationAccuracy = 65
    ) -> Bool {
        horizontalAccuracy >= 0 &&
        horizontalAccuracy <= maximumAccuracy &&
        isFresh(timestamp: timestamp, now: now)
    }
}


enum Polyline6Decoder {
    static func decode(_ encoded: String) -> [RouteCoordinate] {
        let bytes = Array(encoded.utf8)
        var index = 0
        var latitude = 0
        var longitude = 0
        var points: [RouteCoordinate] = []

        func readDelta() -> Int? {
            var result = 0
            var shift = 0
            var byte = 0

            repeat {
                guard index < bytes.count, shift <= 30 else { return nil }
                byte = Int(bytes[index]) - 63
                index += 1
                guard byte >= 0 else { return nil }
                result |= (byte & 0x1f) << shift
                shift += 5
            } while byte >= 0x20

            return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
        }

        while index < bytes.count {
            guard let latitudeDelta = readDelta(),
                  let longitudeDelta = readDelta() else {
                return []
            }

            latitude += latitudeDelta
            longitude += longitudeDelta

            let lat = Double(latitude) / 1_000_000
            let lon = Double(longitude) / 1_000_000
            guard (-90.0...90.0).contains(lat), (-180.0...180.0).contains(lon) else {
                return []
            }
            points.append(RouteCoordinate(latitude: lat, longitude: lon))
        }

        return points
    }
}
