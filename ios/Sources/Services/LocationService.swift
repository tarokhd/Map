import Combine
import CoreLocation
import Foundation

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var errorMessage: String?

    private let manager = CLLocationManager()
    private var shouldUpdateLocation = false

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 3
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = true
    }

    var hasLocationPermission: Bool {
        authorizationStatus == .authorizedAlways ||
        authorizationStatus == .authorizedWhenInUse
    }

    func requestAndStart() {
        errorMessage = nil
        shouldUpdateLocation = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            shouldUpdateLocation = false
            errorMessage = "اجازه دسترسی به موقعیت مکانی در تنظیمات آیفون غیرفعال است."
        @unknown default:
            shouldUpdateLocation = false
            errorMessage = "وضعیت مجوز موقعیت مکانی مشخص نیست."
        }
    }

    func startUpdating() {
        shouldUpdateLocation = true
        manager.activityType = .otherNavigation
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = true
        startIfAuthorizedOrRequestPermission()
    }

    func startNavigationUpdates(for mode: TravelMode) {
        shouldUpdateLocation = true
        manager.activityType = mode == .walking ? .otherNavigation : .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = mode == .walking ? 4 : 3
        manager.pausesLocationUpdatesAutomatically = false
        startIfAuthorizedOrRequestPermission()
    }

    func stopUpdating() {
        shouldUpdateLocation = false
        manager.stopUpdatingLocation()
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .otherNavigation
    }

    private func startIfAuthorizedOrRequestPermission() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            shouldUpdateLocation = false
            errorMessage = "برای مکان‌یابی، اجازه دسترسی به موقعیت را فعال کنید."
        @unknown default:
            shouldUpdateLocation = false
            errorMessage = "وضعیت مجوز موقعیت مکانی مشخص نیست."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        guard shouldUpdateLocation else { return }

        if manager.authorizationStatus == .authorizedAlways ||
            manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        } else if manager.authorizationStatus == .denied ||
                    manager.authorizationStatus == .restricted {
            shouldUpdateLocation = false
            errorMessage = "برای مکان‌یابی، اجازه دسترسی به موقعیت را فعال کنید."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last,
              NavigationLocationQuality.isUsable(
                horizontalAccuracy: latest.horizontalAccuracy,
                timestamp: latest.timestamp
              ) else {
            return
        }
        location = latest
        errorMessage = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = "دریافت موقعیت ناموفق بود: \(error.localizedDescription)"
    }
}
