import Foundation
import CoreLocation
import Combine

// Equatable wrapper for CLLocationCoordinate2D
struct LocationCoordinate: Equatable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var userLocation: LocationCoordinate?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocationPermission() {
        Log.debug("Requesting location permission...")
        manager.requestWhenInUseAuthorization()
    }

    func requestLocation() {
        Log.debug("requestLocation called, status: \(authorizationStatus.rawValue)")
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            Log.debug("Authorized - requesting location update")
            manager.requestLocation()
        } else {
            Log.debug("Not authorized - requesting permission first")
            requestLocationPermission()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        Log.debug("Authorization changed to: \(authorizationStatus.rawValue)")

        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            Log.debug("Now authorized - requesting location")
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.first {
            Log.debug("Got location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            DispatchQueue.main.async {
                self.userLocation = LocationCoordinate(location.coordinate)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Log.error("Location error: \(error)")
    }
}
