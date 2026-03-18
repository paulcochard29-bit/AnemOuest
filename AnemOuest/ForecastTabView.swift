import SwiftUI
import CoreLocation

// MARK: - Forecast Tab View

struct ForecastTabView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var locationManager = LocationManager()
    @StateObject private var favoritesManager = FavoritesManager.shared
    @StateObject private var stationManager = WindStationManager.shared

    @State private var selectedLocation: ForecastLocation?
    @State private var showLocationPicker = false

    var body: some View {
        NavigationStack {
            if let location = selectedLocation {
                // Show forecast for selected location
                ForecastContentView(
                    location: location,
                    onChangeLocation: { showLocationPicker = true }
                )
            } else {
                // Location selector
                locationSelectorView
            }
        }
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerSheet(
                selectedLocation: $selectedLocation,
                isPresented: $showLocationPicker
            )
        }
        .onAppear {
            // Auto-select user location or first favorite
            if selectedLocation == nil {
                if let userLocation = locationManager.userLocation {
                    selectedLocation = ForecastLocation(
                        name: "Ma position",
                        latitude: userLocation.latitude,
                        longitude: userLocation.longitude
                    )
                } else if let firstFavorite = favoritesManager.favorites.first {
                    selectedLocation = ForecastLocation(
                        name: firstFavorite.name,
                        latitude: firstFavorite.latitude,
                        longitude: firstFavorite.longitude
                    )
                }
            }
        }
        .onChange(of: appState.forecastLocation?.name) { _, _ in
            // Update selected location when appState changes
            if let location = appState.forecastLocation {
                selectedLocation = ForecastLocation(
                    name: location.name,
                    latitude: location.latitude,
                    longitude: location.longitude
                )
            }
        }
    }

    private var locationSelectorView: some View {
        VStack(spacing: 20) {
            ContentUnavailableView(
                "Selectionnez un lieu",
                systemImage: "location.magnifyingglass",
                description: Text("Choisissez une station favorite ou utilisez votre position")
            )

            VStack(spacing: 12) {
                // User location button
                if let userLocation = locationManager.userLocation {
                    Button {
                        selectedLocation = ForecastLocation(
                            name: "Ma position",
                            latitude: userLocation.latitude,
                            longitude: userLocation.longitude
                        )
                    } label: {
                        Label("Utiliser ma position", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                // Pick from favorites
                Button {
                    showLocationPicker = true
                } label: {
                    Label("Choisir un lieu", systemImage: "list.bullet")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 40)
        }
        .navigationTitle("Previsions")
    }
}

// MARK: - Forecast Location Model

struct ForecastLocation: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let latitude: Double
    let longitude: Double
}

// MARK: - Forecast Content View (wrapper for ForecastFullView)

private struct ForecastContentView: View {
    let location: ForecastLocation
    let onChangeLocation: () -> Void

    var body: some View {
        ForecastFullView(
            stationName: location.name,
            latitude: location.latitude,
            longitude: location.longitude,
            onClose: { },
            showCloseButton: false  // No close button in tab
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onChangeLocation) {
                    Image(systemName: "location.circle")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.hierarchical)
                }
            }
        }
    }
}

// MARK: - Location Picker Sheet

private struct LocationPickerSheet: View {
    @Binding var selectedLocation: ForecastLocation?
    @Binding var isPresented: Bool

    @StateObject private var favoritesManager = FavoritesManager.shared
    @StateObject private var locationManager = LocationManager()

    var body: some View {
        NavigationStack {
            List {
                // User location
                if let userLocation = locationManager.userLocation {
                    Section("Position actuelle") {
                        Button {
                            selectLocation(
                                name: "Ma position",
                                latitude: userLocation.latitude,
                                longitude: userLocation.longitude
                            )
                        } label: {
                            Label("Ma position", systemImage: "location.fill")
                        }
                    }
                }

                // Favorite stations
                if !favoritesManager.favorites.isEmpty {
                    Section("Stations favorites") {
                        ForEach(favoritesManager.favorites) { favorite in
                            Button {
                                selectLocation(
                                    name: favorite.name,
                                    latitude: favorite.latitude,
                                    longitude: favorite.longitude
                                )
                            } label: {
                                Label(favorite.name, systemImage: "wind")
                            }
                        }
                    }
                }

                // Favorite spots
                if !favoritesManager.favoriteSpots.isEmpty {
                    Section("Spots favoris") {
                        ForEach(favoritesManager.favoriteSpots) { spot in
                            Button {
                                selectLocation(
                                    name: spot.name,
                                    latitude: spot.latitude,
                                    longitude: spot.longitude
                                )
                            } label: {
                                Label(spot.name, systemImage: spot.type.icon)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choisir un lieu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") {
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Helpers

    private func selectLocation(name: String, latitude: Double, longitude: Double) {
        // Update location first
        let newLocation = ForecastLocation(
            name: name,
            latitude: latitude,
            longitude: longitude
        )
        selectedLocation = newLocation

        // Close sheet after a brief delay to ensure binding propagates
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isPresented = false
        }
    }
}

#Preview {
    ForecastTabView()
}
