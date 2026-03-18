import Foundation

// MARK: - NDBC Service (National Data Buoy Center)

final class NDBCService {
    static let shared = NDBCService()
    private init() {}

    private let apiURL = "\(AppConstants.API.anemOuestAPI)/ndbc"

    // MARK: - API Response Models

    private struct StationsResponse: Decodable {
        let stations: [NDBCStation]
    }

    private struct NDBCStation: Decodable {
        let id: String
        let name: String
        let lat: Double
        let lon: Double
        let wind: Double
        let gust: Double
        let direction: Double
        let isOnline: Bool
        let ts: String?
        let temperature: Double?
        let waterTemp: Double?
        let pressure: Double?
    }

    private struct HistoryResponse: Decodable {
        let observations: [NDBCObservation]
    }

    private struct NDBCObservation: Decodable {
        let ts: String
        let wind: Double
        let gust: Double?
        let dir: Double
        let temperature: Double?
        let waterTemp: Double?
        let pressure: Double?
    }

    // MARK: - Fetch Stations

    func fetchStationsFromVercel() async -> [WindStation] {
        guard let url = URL(string: apiURL) else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(AppConstants.API.key, forHTTPHeaderField: "X-Api-Key")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(StationsResponse.self, from: data)

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallbackFormatter = ISO8601DateFormatter()

            return response.stations.map { s in
                let lastUpdate: Date?
                if let ts = s.ts {
                    lastUpdate = isoFormatter.date(from: ts) ?? fallbackFormatter.date(from: ts)
                } else {
                    lastUpdate = nil
                }

                return WindStation(
                    id: s.id,
                    name: s.name,
                    latitude: s.lat,
                    longitude: s.lon,
                    wind: s.wind,
                    gust: s.gust,
                    direction: s.direction,
                    isOnline: s.isOnline,
                    source: .ndbc,
                    lastUpdate: lastUpdate,
                    pressure: s.pressure,
                    temperature: s.temperature
                )
            }
        } catch {
            Log.network("NDBC fetch error: \(error)")
            return []
        }
    }

    // MARK: - Fetch History

    func fetchHistory(stationId: String, hours: Int = 48) async -> [WCWindObservation] {
        guard let url = URL(string: "\(apiURL)?history=\(stationId)&hours=\(hours)") else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(AppConstants.API.key, forHTTPHeaderField: "X-Api-Key")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(HistoryResponse.self, from: data)

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallbackFormatter = ISO8601DateFormatter()

            return response.observations.compactMap { obs in
                guard let date = isoFormatter.date(from: obs.ts) ?? fallbackFormatter.date(from: obs.ts) else {
                    return nil
                }
                let ts = date.timeIntervalSince1970

                return WCWindObservation(
                    ts: ts,
                    ws: WCWindSpeed(
                        moy: WCScalar(obs.wind),
                        max: WCScalar(obs.gust ?? obs.wind)
                    ),
                    wd: WCWindDir(
                        moy: WCScalar(obs.dir)
                    )
                )
            }
        } catch {
            Log.network("NDBC history error: \(error)")
            return []
        }
    }
}
