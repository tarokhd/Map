import Combine
import CoreLocation
import Foundation

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var errorMessage: String?

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 3
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = true
    }

    func requestAndStart() {
        errorMessage = nil
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            errorMessage = "اجازه موقعیت مکانی در تنظیمات آیفون غیرفعال است."
        @unknown default:
            errorMessage = "وضعیت مجوز موقعیت مکانی مشخص نیست."
        }
    }

    func startUpdating() {
        guard manager.authorizationStatus == .authorizedAlways ||
                manager.authorizationStatus == .authorizedWhenInUse else {
            requestAndStart()
            return
        }
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedAlways ||
            manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        } else if manager.authorizationStatus == .denied ||
                    manager.authorizationStatus == .restricted {
            errorMessage = "برای مکان‌یابی، اجازه دسترسی به موقعیت را فعال کنید."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        let age = abs(latest.timestamp.timeIntervalSinceNow)
        guard age <= 20, latest.horizontalAccuracy >= 0 else { return }
        location = latest
        errorMessage = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = "دریافت موقعیت ناموفق بود: \(error.localizedDescription)"
    }
}
