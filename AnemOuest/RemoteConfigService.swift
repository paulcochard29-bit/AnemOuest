import Foundation
import SwiftUI
import Combine

// MARK: - Remote Config Service

/// Fetches app configuration from the admin API and writes values
/// directly to UserDefaults so all @AppStorage bindings update automatically.
class RemoteConfigService: ObservableObject {
    static let shared = RemoteConfigService()

    // MARK: - Published State (for SwiftUI observation)

    @Published var maintenanceMode: Bool = false
    @Published var maintenanceMessage: String = ""
    @Published var isLoaded: Bool = false

    // Feature flags (control tab visibility)
    @Published var enableFishing: Bool = true
    @Published var enableForecasts: Bool = true
    @Published var enableWebcams: Bool = true
    @Published var enableWaveBuoys: Bool = true
    private let cacheKey = "remote_config_cache"

    private init() {
        loadCachedConfig()
    }

    // MARK: - Fetch Config

    func fetchConfig() async {
        let urlString = "\(AppConstants.API.anemOuestAPI)/spots?type=config&_t=\(Int(Date().timeIntervalSince1970))"
        guard let url = URL(string: urlString) else { return }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue(AppConstants.API.key, forHTTPHeaderField: "X-Api-Key")
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                Log.error("Remote config fetch failed: bad status")
                return
            }

            guard let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Log.error("Remote config: invalid JSON")
                return
            }

            // Cache the raw data
            UserDefaults.standard.set(data, forKey: cacheKey)

            await MainActor.run {
                applyConfig(config)
                isLoaded = true
            }

            Log.debug("Remote config loaded: \(config.count) keys")
        } catch {
            Log.error("Remote config fetch error: \(error.localizedDescription)")
        }
    }

    // MARK: - Apply Config

    /// Writes remote config values directly into UserDefaults.
    /// This makes all @AppStorage bindings across the app update automatically.
    private func applyConfig(_ config: [String: Any]) {
        let defaults = UserDefaults.standard

        // Maintenance (only @Published, not in UserDefaults)
        maintenanceMode = config["maintenanceMode"] as? Bool ?? false
        maintenanceMessage = config["maintenanceMessage"] as? String ?? ""

        // Feature flags (@Published for tab visibility)
        enableFishing = config["enableFishing"] as? Bool ?? true
        enableForecasts = config["enableForecasts"] as? Bool ?? true
        enableWebcams = config["enableWebcams"] as? Bool ?? true
        enableWaveBuoys = config["enableWaveBuoys"] as? Bool ?? true

        // Wind sources → write to UserDefaults ONLY if user hasn't customized them
        // Once the user touches any source toggle, remote config stops overriding sources
        let userCustomizedSources = defaults.bool(forKey: "user_customized_sources")

        if !userCustomizedSources {
            let sourceMap: [String: String] = [
                "sourceWindCornouaille": "source_windcornouaille",
                "sourceFFVL": "source_ffvl",
                "sourcePioupiou": "source_pioupiou",
                "sourceHolfuy": "source_holfuy",
                "sourceWindguru": "source_windguru",
                "sourceWindsUp": "source_windsup",
                "sourceMeteoFrance": "source_meteofrance",
                "sourceDiabox": "source_diabox",
                "sourceNetatmo": "source_netatmo"
            ]
            for (configKey, storageKey) in sourceMap {
                if let value = config[configKey] as? Bool {
                    defaults.set(value, forKey: storageKey)
                }
            }
        }

        // Spot display → write to UserDefaults
        if let v = config["showKiteSpots"] as? Bool {
            defaults.set(v, forKey: "showKiteSpots")
        }
        if let v = config["showSurfSpots"] as? Bool {
            defaults.set(v, forKey: "showSurfSpots")
        }
        if let v = config["showParaglidingSpots"] as? Bool {
            defaults.set(v, forKey: "showParaglidingSpots")
        }
        if let v = config["showTideWidget"] as? Bool {
            defaults.set(v, forKey: "showTideWidget")
        }

        // Wind unit → write to UserDefaults
        if let v = config["defaultWindUnit"] as? String {
            defaults.set(v, forKey: "windUnit")
        }

        // Refresh interval → write to UserDefaults (only if user hasn't customized)
        if !defaults.bool(forKey: "user_customized_refresh") {
            if let v = config["defaultRefreshInterval"] as? Int {
                defaults.set(Double(v), forKey: "refreshIntervalSeconds")
            } else if let v = config["defaultRefreshInterval"] as? Double {
                defaults.set(v, forKey: "refreshIntervalSeconds")
            }
        }

        // Kite thresholds → write to UserDefaults
        if let v = config["kiteMaxWind"] as? Int {
            defaults.set(v, forKey: "kiteMaxWindThreshold")
        } else if let v = config["kiteMaxWind"] as? Double {
            defaults.set(Int(v), forKey: "kiteMaxWindThreshold")
        }
        if let v = config["kiteMinWind"] as? Int {
            defaults.set(v, forKey: "kiteMinWindThreshold")
        } else if let v = config["kiteMinWind"] as? Double {
            defaults.set(Int(v), forKey: "kiteMinWindThreshold")
        }
        if let v = config["kiteMaxGust"] as? Int {
            defaults.set(v, forKey: "kiteMaxGustThreshold")
        } else if let v = config["kiteMaxGust"] as? Double {
            defaults.set(Int(v), forKey: "kiteMaxGustThreshold")
        }

        // Quiet hours → write as dictionary (matches NotificationManager format)
        var quietHoursChanged = false
        var quietHours = defaults.dictionary(forKey: "quietHoursSettings") ?? [
            "enabled": false, "start": 22, "end": 7
        ]
        if let v = config["quietHoursEnabled"] as? Bool {
            quietHours["enabled"] = v
            quietHoursChanged = true
        }
        if let v = config["quietHoursStart"] as? Int {
            quietHours["start"] = v
            quietHoursChanged = true
        }
        if let v = config["quietHoursEnd"] as? Int {
            quietHours["end"] = v
            quietHoursChanged = true
        }
        if quietHoursChanged {
            defaults.set(quietHours, forKey: "quietHoursSettings")
            // Notify NotificationManager to reload
            NotificationCenter.default.post(name: .init("quietHoursSettingsChanged"), object: nil)
        }

        // Map defaults → write to UserDefaults
        if let v = config["defaultMapLat"] as? Double {
            defaults.set(v, forKey: "defaultMapLat")
        }
        if let v = config["defaultMapLon"] as? Double {
            defaults.set(v, forKey: "defaultMapLon")
        }
        if let v = config["defaultMapZoom"] as? Int {
            defaults.set(v, forKey: "defaultMapZoom")
        } else if let v = config["defaultMapZoom"] as? Double {
            defaults.set(Int(v), forKey: "defaultMapZoom")
        }
    }

    // MARK: - Cache

    private func loadCachedConfig() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        applyConfig(config)
        isLoaded = true
    }
}
