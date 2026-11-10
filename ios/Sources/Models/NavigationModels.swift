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
        let action: String
        switch type {
        case 1, 2, 3: action = "حرکت را آغاز کنید"
        case 4, 5, 6: action = "به مقصد رسیده‌اید"
        case 7, 8, 22: action = "به مسیر مستقیم ادامه دهید"
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
        case 23: action = "در سمت راست مسیر بمانید"
        case 24: action = "در سمت چپ مسیر بمانید"
        case 25, 37, 38: action = "به مسیر ادغام شوید"
        case 26: action = "وارد میدان شوید"
        case 27: action = "از میدان خارج شوید"
        case 28: action = "وارد مسیر کشتی شوید"
        case 29: action = "از مسیر کشتی خارج شوید"
        default: action = "به مسیر ادامه دهید"
        }

        let street = streetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !street.isEmpty, street.lowercased() != "unnamed road" else { return action }
        return "\(action) و وارد \(street) شوید"
    }

    static func distance(_ meters: Double) -> String {
        let safe = max(0, meters)
        if safe >= 1_000 {
            let kilometers = safe / 1_000
            let value = kilometers < 10
                ? String(format: "%.1f", kilometers)
                : String(Int(kilometers.rounded()))
            return "\(persianDigits(value)) کیلومتر"
        }
        return "\(persianDigits(String(Int(safe.rounded())))) متر"
    }

    static func duration(_ seconds: Double) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 {
            return "\(persianDigits(String(hours))) ساعت و \(persianDigits(String(remainder))) دقیقه"
        }
        return "\(persianDigits(String(minutes))) دقیقه"
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
