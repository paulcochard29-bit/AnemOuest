import SwiftUI

// MARK: - Favorites Tab View

struct FavoritesTabView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var favoritesManager = FavoritesManager.shared
    @StateObject private var stationManager = WindStationManager.shared
    @StateObject private var waveBuoyService = WaveBuoyService.shared

    @State private var selectedSpotForConfig: FavoriteSpot?
    @State private var selectedStationForConfig: FavoriteStation?

    var body: some View {
        NavigationStack {
            List {
                // Wind Stations Section
                if !favoritesManager.favorites.isEmpty {
                    Section {
                        ForEach(favoritesManager.favorites) { favorite in
                            FavoriteStationRow(
                                favorite: favorite,
                                station: findStation(for: favorite),
                                onTap: {
                                    appState.showStationOnMap(stationId: favorite.id)
                                },
                                onForecast: {
                                    appState.showForecast(
                                        name: favorite.name,
                                        latitude: favorite.latitude,
                                        longitude: favorite.longitude
                                    )
                                },
                                onConfigure: {
                                    selectedStationForConfig = favorite
                                }
                            )
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    favoritesManager.removeFavorite(id: favorite.id)
                                } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Label("Stations", systemImage: "wind")
                    }
                }

                // Wave Buoys Section
                if !favoritesManager.favoriteWaveBuoys.isEmpty {
                    Section {
                        ForEach(favoritesManager.favoriteWaveBuoys) { favorite in
                            FavoriteWaveBuoyRow(
                                favorite: favorite,
                                buoy: waveBuoyService.buoys.first { $0.id == favorite.id },
                                onTap: {
                                    appState.showWaveBuoyOnMap(buoyId: favorite.id)
                                },
                                onForecast: {
                                    appState.showForecast(
                                        name: favorite.name,
                                        latitude: favorite.latitude,
                                        longitude: favorite.longitude
                                    )
                                }
                            )
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    favoritesManager.removeFavoriteBuoy(id: favorite.id)
                                } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Label("Bouees", systemImage: "water.waves")
                    }
                }

                // Kite/Surf Spots Section
                if !favoritesManager.favoriteSpots.isEmpty {
                    Section {
                        ForEach(favoritesManager.favoriteSpots) { spot in
                            FavoriteSpotRow(
                                spot: spot,
                                nearestStation: findNearestStation(for: spot),
                                onTap: {
                                    if spot.type == .kite {
                                        appState.showKiteSpotOnMap(spotId: spot.id)
                                    } else {
                                        appState.showSurfSpotOnMap(spotId: spot.id)
                                    }
                                },
                                onForecast: {
                                    appState.showForecast(
                                        name: spot.name,
                                        latitude: spot.latitude,
                                        longitude: spot.longitude
                                    )
                                },
                                onConfigure: {
                                    selectedSpotForConfig = spot
                                }
                            )
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    favoritesManager.removeSpotFavorite(id: spot.id)
                                } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Label("Spots", systemImage: "mappin.and.ellipse")
                    }
                }

                // Empty State
                if favoritesManager.favorites.isEmpty &&
                   favoritesManager.favoriteWaveBuoys.isEmpty &&
                   favoritesManager.favoriteSpots.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "Aucun favori",
                            systemImage: "heart.slash",
                            description: Text("Ajoutez des stations ou spots en favoris depuis la carte")
                        )
                    }
                }
            }
            .navigationTitle("Favoris")
            .refreshable {
                await refreshData()
            }
            .sheet(item: $selectedSpotForConfig) { spot in
                SpotAlertConfigView(spot: spot)
            }
            .sheet(item: $selectedStationForConfig) { station in
                WindAlertConfigView(stationId: station.id, stationName: station.name)
            }
        }
    }

    // MARK: - Helpers

    /// Find the matching WindStation for a favorite
    private func findStation(for favorite: FavoriteStation) -> WindStation? {
        stationManager.stations.first { $0.stableId == favorite.id }
    }

    /// Find the nearest online wind station for a favorite spot
    private func findNearestStation(for spot: FavoriteSpot) -> WindStation? {
        let onlineStations = stationManager.stations.filter { $0.isOnline && !$0.name.contains("Concorde") && !($0.wind == 0 && $0.gust == 0) }
        guard !onlineStations.isEmpty else { return nil }

        return onlineStations.min(by: { a, b in
            let dA = distance(lat1: spot.latitude, lon1: spot.longitude, lat2: a.latitude, lon2: a.longitude)
            let dB = distance(lat1: spot.latitude, lon1: spot.longitude, lat2: b.latitude, lon2: b.longitude)
            return dA < dB
        })
    }

    /// Haversine distance in km
    private func distance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon / 2) * sin(dLon / 2)
        return R * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    // MARK: - Actions


    private func refreshData() async {
        await stationManager.refresh(sources: Set(WindSource.allCases))
        await waveBuoyService.fetchBuoys()
    }
}

// MARK: - Favorite Station Row

private struct FavoriteStationRow: View {
    let favorite: FavoriteStation
    let station: WindStation?
    let onTap: () -> Void
    let onForecast: () -> Void
    let onConfigure: () -> Void

    private var isOnline: Bool {
        station?.isOnline ?? false
    }

    private var windSpeed: Double {
        station?.wind ?? 0
    }

    private var gustSpeed: Double {
        station?.gust ?? 0
    }

    private var windDirection: Double {
        station?.direction ?? 0
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Wind indicator
                ZStack {
                    Circle()
                        .fill(windColor.opacity(0.15))
                        .frame(width: 44, height: 44)

                    if isOnline {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(windColor)
                            .rotationEffect(.degrees(windDirection + 180))
                    } else {
                        Image(systemName: "minus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(favorite.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if NotificationManager.shared.hasAlert(for: favorite.id) {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                        }
                    }

                    if isOnline {
                        Text("\(WindUnit.convertValue(windSpeed))/\(WindUnit.convertValue(gustSpeed)) \(WindUnit.current.symbol)")
                            .font(.subheadline)
                            .foregroundStyle(windColor)
                    } else {
                        Text("Hors ligne")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    onConfigure()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("Voir sur la carte", systemImage: "map")
            }

            Button {
                onForecast()
            } label: {
                Label("Voir les prévisions", systemImage: "cloud.sun")
            }

            Button {
                onConfigure()
            } label: {
                Label("Configurer les alertes", systemImage: "bell.badge")
            }
        }
    }

    private var windColor: Color {
        guard isOnline else { return .gray }
        return windScale(windSpeed)
    }
}

// MARK: - Favorite Wave Buoy Row

private struct FavoriteWaveBuoyRow: View {
    let favorite: FavoriteWaveBuoy
    let buoy: WaveBuoy?
    let onTap: () -> Void
    let onForecast: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Wave indicator
                ZStack {
                    Circle()
                        .fill(waveColor.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "water.waves")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(waveColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(favorite.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let buoy = buoy, buoy.status.isOnline, let hm0 = buoy.hm0 {
                        HStack(spacing: 4) {
                            Text(String(format: "%.1fm", hm0))
                            if let tp = buoy.tp {
                                Text("@")
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.1fs", tp))
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(waveColor)
                    } else {
                        Text("Hors ligne")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("Voir sur la carte", systemImage: "map")
            }

            Button {
                onForecast()
            } label: {
                Label("Voir les prévisions", systemImage: "cloud.sun")
            }
        }
    }

    private var waveColor: Color {
        guard let buoy = buoy, buoy.status.isOnline, let hm0 = buoy.hm0 else { return .gray }
        switch hm0 {
        case ..<0.5: return .cyan
        case ..<1.0: return .teal
        case ..<1.5: return .green
        case ..<2.0: return .yellow
        case ..<2.5: return .orange
        case ..<3.0: return .red
        default: return .purple
        }
    }
}

// MARK: - Favorite Spot Row

private struct FavoriteSpotRow: View {
    let spot: FavoriteSpot
    let nearestStation: WindStation?
    let onTap: () -> Void
    let onForecast: () -> Void
    let onConfigure: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(spotColor.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: spot.type.icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(spotColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(spot.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if spot.alertSettings?.isEnabled == true {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                        }
                    }

                    HStack(spacing: 4) {
                        Text(spot.type.displayName)
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(spot.orientation)

                        if let station = nearestStation {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text("\(WindUnit.convertValue(station.wind))/\(WindUnit.convertValue(station.gust)) \(WindUnit.current.symbol)")
                                .foregroundStyle(windScale(station.wind))
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onConfigure()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("Voir sur la carte", systemImage: "map")
            }

            Button {
                onForecast()
            } label: {
                Label("Voir les previsions", systemImage: "cloud.sun")
            }

            Button {
                onConfigure()
            } label: {
                Label("Configurer les alertes", systemImage: "gearshape")
            }
        }
    }

    private var spotColor: Color {
        switch spot.type {
        case .kite: return .orange
        case .surf: return .cyan
        }
    }
}

#Preview {
    FavoritesTabView()
}
