import SwiftUI
import CoreLocation
import Combine

// MARK: - App State (Shared between tabs)

/// Observable state shared across all tabs for cross-tab navigation and communication
class AppState: ObservableObject {
    // MARK: - Navigation State

    /// Station ID to show on map (set from Favorites tab)
    @Published var selectedStationId: String?

    /// Kite spot ID to show on map
    @Published var selectedKiteSpotId: String?

    /// Surf spot ID to show on map
    @Published var selectedSurfSpotId: String?

    /// Wave buoy ID to show on map
    @Published var selectedWaveBuoyId: String?

    /// Trigger navigation to Map tab
    @Published var shouldNavigateToMap: Bool = false

    /// Coordinate to center on map
    @Published var centerOnCoordinate: CLLocationCoordinate2D?

    /// Forecast location (set from Favorites tab)
    @Published var forecastLocation: (name: String, latitude: Double, longitude: Double)?

    /// Trigger navigation to Forecast tab
    @Published var shouldNavigateToForecast: Bool = false

    // MARK: - Deep Link Methods

    /// Navigate to map and show a specific station
    func showStationOnMap(stationId: String) {
        selectedStationId = stationId
        selectedKiteSpotId = nil
        selectedSurfSpotId = nil
        selectedWaveBuoyId = nil
        shouldNavigateToMap = true
    }

    /// Navigate to map and show a specific kite spot
    func showKiteSpotOnMap(spotId: String) {
        selectedStationId = nil
        selectedKiteSpotId = spotId
        selectedSurfSpotId = nil
        selectedWaveBuoyId = nil
        shouldNavigateToMap = true
    }

    /// Navigate to map and show a specific surf spot
    func showSurfSpotOnMap(spotId: String) {
        selectedStationId = nil
        selectedKiteSpotId = nil
        selectedSurfSpotId = spotId
        selectedWaveBuoyId = nil
        shouldNavigateToMap = true
    }

    /// Navigate to map and show a specific wave buoy
    func showWaveBuoyOnMap(buoyId: String) {
        selectedStationId = nil
        selectedKiteSpotId = nil
        selectedSurfSpotId = nil
        selectedWaveBuoyId = buoyId
        shouldNavigateToMap = true
    }

    /// Navigate to map and center on a coordinate
    func centerMapOn(coordinate: CLLocationCoordinate2D) {
        centerOnCoordinate = coordinate
        shouldNavigateToMap = true
    }

    /// Clear all navigation state
    func clearNavigationState() {
        selectedStationId = nil
        selectedKiteSpotId = nil
        selectedSurfSpotId = nil
        selectedWaveBuoyId = nil
        centerOnCoordinate = nil
    }

    // MARK: - Forecast Navigation

    /// Navigate to forecast tab with a specific location
    func showForecast(name: String, latitude: Double, longitude: Double) {
        forecastLocation = (name: name, latitude: latitude, longitude: longitude)
        shouldNavigateToForecast = true
    }

    /// Clear forecast navigation state
    func clearForecastNavigation() {
        shouldNavigateToForecast = false
    }
}

// MARK: - Environment Key

struct AppStateKey: EnvironmentKey {
    static let defaultValue: AppState = AppState()
}

extension EnvironmentValues {
    var appState: AppState {
        get { self[AppStateKey.self] }
        set { self[AppStateKey.self] = newValue }
    }
}
