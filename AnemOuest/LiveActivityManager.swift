import Foundation
import ActivityKit
import Combine

// MARK: - Shared Activity Attributes (must match widget definition)

struct WindLiveActivityAttributes: ActivityAttributes {
    let stationName: String
    let stationId: String

    struct ContentState: Codable, Hashable {
        let wind: Double
        let gust: Double
        let direction: Double
        let isOnline: Bool
        let unit: String
        let lastUpdate: Date
    }
}

// MARK: - Live Activity Manager

@MainActor
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    @Published var isTracking: Bool = false
    @Published var trackedStationId: String?

    private var currentActivity: Activity<WindLiveActivityAttributes>?

    func startTracking(stationId: String, stationName: String, wind: Double, gust: Double, direction: Double, isOnline: Bool) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Log.debug("Live Activities not enabled")
            return
        }

        // Stop existing activity
        stopTracking()

        let attributes = WindLiveActivityAttributes(
            stationName: stationName,
            stationId: stationId
        )

        let unit = UserDefaults.standard.string(forKey: "selectedWindUnit") ?? "Nœuds"
        let state = WindLiveActivityAttributes.ContentState(
            wind: wind,
            gust: gust,
            direction: direction,
            isOnline: isOnline,
            unit: unitSymbol(unit),
            lastUpdate: Date()
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: Date().addingTimeInterval(600))
            )
            currentActivity = activity
            trackedStationId = stationId
            isTracking = true
            Log.debug("Live Activity started for \(stationName)")
        } catch {
            Log.debug("Failed to start Live Activity: \(error)")
        }
    }

    func updateTracking(wind: Double, gust: Double, direction: Double, isOnline: Bool) {
        guard let activity = currentActivity else { return }

        let unit = UserDefaults.standard.string(forKey: "selectedWindUnit") ?? "Nœuds"
        let state = WindLiveActivityAttributes.ContentState(
            wind: wind,
            gust: gust,
            direction: direction,
            isOnline: isOnline,
            unit: unitSymbol(unit),
            lastUpdate: Date()
        )

        Task {
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(600)))
        }
    }

    func stopTracking() {
        guard let activity = currentActivity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        currentActivity = nil
        trackedStationId = nil
        isTracking = false
    }

    private func unitSymbol(_ raw: String) -> String {
        switch raw {
        case "km/h": return "km/h"
        case "m/s": return "m/s"
        case "mph": return "mph"
        default: return "nds"
        }
    }
}
