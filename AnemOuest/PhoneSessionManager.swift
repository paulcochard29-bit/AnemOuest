//
//  PhoneSessionManager.swift
//  AnemOuest
//
//  Handles WatchConnectivity to sync data with Apple Watch
//

import Foundation
import WatchConnectivity
import Combine

@MainActor
final class PhoneSessionManager: NSObject, ObservableObject {
    static let shared = PhoneSessionManager()

    @Published var isWatchAppInstalled: Bool = false
    @Published var isReachable: Bool = false

    private var session: WCSession?

    override init() {
        super.init()

        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    // MARK: - Send Favorites to Watch

    func sendFavoritesToWatch(_ favorites: [FavoriteStation], stations: [WindStation]) {
        guard let session = session, session.activationState == .activated else {
            Log.debug("Phone: WCSession not activated")
            return
        }

        // Convert favorites to Watch format
        var watchStations: [WatchStationDataForPhone] = []

        for favorite in favorites {
            if let station = stations.first(where: { $0.stableId == favorite.id }) {
                watchStations.append(WatchStationDataForPhone(
                    id: station.stableId,
                    name: station.name,
                    source: station.source.displayName,
                    wind: station.wind,
                    gust: station.gust,
                    direction: station.direction,
                    isOnline: isOnline(station.lastUpdate),
                    lastUpdate: station.lastUpdate,
                    latitude: station.latitude,
                    longitude: station.longitude
                ))
            }
        }

        // Encode and send (stations + favorite IDs)
        do {
            let stationsData = try JSONEncoder().encode(watchStations)
            let favoriteIdsData = try JSONEncoder().encode(favorites.map(\.id))
            let payload: [String: Any] = [
                "stations": stationsData,
                "favoriteIds": favoriteIdsData
            ]

            // Try to send immediately if reachable
            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil) { error in
                    Log.debug("Phone: Error sending message: \(error)")
                }
            }

            // Also update application context for background sync
            try session.updateApplicationContext(payload)
            Log.debug("Phone: Sent \(watchStations.count) stations + \(favorites.count) favorite IDs to Watch")

        } catch {
            Log.debug("Phone: Failed to encode stations: \(error)")
        }
    }

    private func isOnline(_ date: Date?) -> Bool {
        guard let date = date else { return false }
        return Date().timeIntervalSince(date) <= 20 * 60
    }
}

// MARK: - WCSessionDelegate

extension PhoneSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            Log.debug("Phone: Session activated: \(activationState.rawValue)")
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isReachable = session.isReachable
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Log.debug("Phone: Session became inactive")
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Log.debug("Phone: Session deactivated")
        // Reactivate for switching watches
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isReachable = session.isReachable
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    // Handle data request from Watch
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if message["request"] as? String == "favorites" {
            Task { @MainActor in
                // Get current favorites and send them
                let favorites = FavoritesManager.shared.favorites
                let stations = WindStationManager.shared.stations

                var watchStations: [WatchStationDataForPhone] = []

                for favorite in favorites {
                    if let station = stations.first(where: { $0.stableId == favorite.id }) {
                        watchStations.append(WatchStationDataForPhone(
                            id: station.stableId,
                            name: station.name,
                            source: station.source.displayName,
                            wind: station.wind,
                            gust: station.gust,
                            direction: station.direction,
                            isOnline: self.isOnline(station.lastUpdate),
                            lastUpdate: station.lastUpdate,
                            latitude: station.latitude,
                            longitude: station.longitude
                        ))
                    } else {
                        // Station not found
                        watchStations.append(WatchStationDataForPhone(
                            id: favorite.id,
                            name: favorite.name,
                            source: favorite.source,
                            wind: 0,
                            gust: 0,
                            direction: 0,
                            isOnline: false,
                            lastUpdate: nil,
                            latitude: favorite.latitude,
                            longitude: favorite.longitude
                        ))
                    }
                }

                do {
                    let stationsData = try JSONEncoder().encode(watchStations)
                    let favoriteIdsData = try JSONEncoder().encode(favorites.map(\.id))
                    replyHandler([
                        "stations": stationsData,
                        "favoriteIds": favoriteIdsData
                    ])
                } catch {
                    replyHandler([:])
                }
            }
        }
    }
}

// MARK: - Watch Station Data (Phone-side encoding)

struct WatchStationDataForPhone: Codable {
    let id: String
    let name: String
    let source: String
    let wind: Double
    let gust: Double
    let direction: Double
    let isOnline: Bool
    let lastUpdate: Date?
    let latitude: Double?
    let longitude: Double?
}
