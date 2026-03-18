import SwiftUI

struct ContentView: View {
    @StateObject private var data = WatchDataManager()

    var body: some View {
        TabView {
            FavoritesView()
            WatchMapView()
            WatchTideView()
        }
        .environmentObject(data)
    }
}

// MARK: - Favorites View

struct FavoritesView: View {
    @EnvironmentObject var data: WatchDataManager

    var body: some View {
        NavigationStack {
            Group {
                if data.favorites.isEmpty && !data.isLoadingFavorites {
                    EmptyFavoritesView(isReachable: data.isReachable) {
                        data.requestFavorites()
                    }
                } else if data.favorites.isEmpty && data.isLoadingFavorites {
                    ProgressView("Chargement...")
                        .font(.system(size: 12))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(data.favorites) { station in
                                NavigationLink {
                                    StationDetailView(station: station)
                                } label: {
                                    StationCard(station: station)
                                }
                                .buttonStyle(.plain)
                            }

                            if let sync = data.lastSync {
                                SyncLabel(date: sync)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
            .navigationTitle("Le Vent")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        data.requestFavorites()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                    }
                }
            }
        }
        .task {
            data.requestFavorites()
            // Fallback: si pas de favoris apres 2s, charger les stations directement
            try? await Task.sleep(for: .seconds(2))
            if data.favorites.isEmpty {
                await data.fetchFavoritesFromAPI()
            }
        }
    }
}

// MARK: - Station Card

struct StationCard: View {
    let station: WatchStation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(station.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Circle()
                    .fill(station.isOnline ? .green : .red.opacity(0.5))
                    .frame(width: 6, height: 6)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(station.windInt)")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(station.windColor)

                Text("/\(station.gustInt)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(station.gustColor)

                Text("nds")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 1)

                Spacer()

                VStack(spacing: 1) {
                    WindArrow(direction: station.direction, size: 24)
                    Text(station.cardinalDirection)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(station.windColor.opacity(0.12))
        )
        .opacity(station.isOnline ? 1.0 : 0.45)
    }
}

// MARK: - Wind Arrow

struct WindArrow: View {
    let direction: Double
    let size: CGFloat

    var body: some View {
        Image(systemName: "location.north.fill")
            .font(.system(size: size * 0.55, weight: .bold))
            .foregroundStyle(.cyan)
            .rotationEffect(.degrees(direction))
            .frame(width: size, height: size)
    }
}

// MARK: - Station Detail

struct StationDetailView: View {
    let station: WatchStation

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(station.isOnline ? .green : .red)
                        .frame(width: 7, height: 7)
                    Text(station.isOnline ? "En ligne" : "Hors ligne")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if !station.timeAgo.isEmpty {
                        Text("- \(station.timeAgo)")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [station.windColor.opacity(0.3), .clear],
                                center: .center, startRadius: 0, endRadius: 50
                            )
                        )
                        .frame(width: 100, height: 100)

                    VStack(spacing: 0) {
                        Text("\(station.windInt)")
                            .font(.system(size: 38, weight: .heavy, design: .rounded))
                            .foregroundStyle(station.windColor)
                        Text("noeuds")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 20) {
                    VStack(spacing: 3) {
                        WindArrow(direction: station.direction, size: 36)
                        Text(station.cardinalDirection)
                            .font(.system(size: 12, weight: .bold))
                        Text("\(Int(station.direction))\u{00B0}")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    Rectangle()
                        .fill(.white.opacity(0.15))
                        .frame(width: 1, height: 40)

                    VStack(spacing: 3) {
                        Text("\(station.gustInt)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(station.gustColor)
                        Text("Rafales")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(station.sourceLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
        .navigationTitle(station.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sync Label

struct SyncLabel: View {
    let date: Date

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 10))
        }
        .foregroundStyle(.tertiary)
        .padding(.top, 4)
    }

    private var text: String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 60 { return "A l'instant" }
        if s < 3600 { return "Il y a \(s / 60) min" }
        return "Il y a \(s / 3600)h"
    }
}

// MARK: - Empty Favorites

struct EmptyFavoritesView: View {
    let isReachable: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: isReachable ? "heart" : "iphone.slash")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text(isReachable ? "Aucun favori" : "iPhone non connecte")
                .font(.system(size: 13, weight: .medium))

            if isReachable {
                Text("Ajoutez des favoris\ndans l'app iPhone")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Chargement direct...")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Button(action: onRefresh) {
                Label("Actualiser", systemImage: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .tint(.cyan)
        }
    }
}

#Preview {
    ContentView()
}
