import Foundation
import CoreLocation

// MARK: - Sensor

struct SensorConfig: Identifiable, Hashable {
    let id: String            // backend sensor id as String
    let name: String
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: SensorConfig, rhs: SensorConfig) -> Bool {
        lhs.id == rhs.id
        && lhs.name == rhs.name
        && lhs.coordinate.latitude == rhs.coordinate.latitude
        && lhs.coordinate.longitude == rhs.coordinate.longitude
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        // quantize to avoid floating hash instability
        hasher.combine(Int((coordinate.latitude * 1_000_000).rounded()))
        hasher.combine(Int((coordinate.longitude * 1_000_000).rounded()))
    }
}

// MARK: - Wind observation

struct WCScalar: Codable, Hashable {
    let raw: Double?
    var value: Double? { raw }

    init(_ v: Double?) { self.raw = v }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            raw = nil
        } else if let d = try? c.decode(Double.self) {
            raw = d
        } else if let i = try? c.decode(Int.self) {
            raw = Double(i)
        } else if let s = try? c.decode(String.self) {
            let normalized = s.replacingOccurrences(of: ",", with: ".")
            raw = Double(normalized)
        } else {
            raw = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }
}

struct WCWindSpeed: Codable, Hashable {
    let moy: WCScalar // mean wind
    let max: WCScalar // gust
}

struct WCWindDir: Codable, Hashable {
    let moy: WCScalar // degrees
}

struct WCWindObservation: Codable, Hashable {
    let ts: TimeInterval // seconds
    let ws: WCWindSpeed
    let wd: WCWindDir
}

// MARK: - Chart samples

enum SeriesKind: String, Codable {
    case wind
    case gust
}

struct WCChartSample: Identifiable, Hashable {
    let id: String
    let t: Date
    let value: Double
    let kind: SeriesKind
}
// MARK: - WindService helpers used by WindViewModel

extension WindService {

    struct ChartResult {
        let latest: WCWindObservation
        let samples: [WCChartSample]
    }

    /// Fetch chart observations and return chart samples + latest.
    static func fetchChart(sensorId: String, timeFrame: Int) async throws -> ChartResult {
        let tf = max(1, timeFrame)
        let url = URL(string: "https://backend.windmorbihan.com/observations/chart.json?sensor=\(sensorId)&time_frame=\(tf)")!

        let (data, resp) = try await URLSession.shared.data(from: url)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        let observations = try decodeObservations(from: data, decoder: decoder)

        guard let latest = observations.max(by: { $0.ts < $1.ts }) else {
            throw URLError(.cannotParseResponse)
        }

        let samples: [WCChartSample] = observations
            .sorted(by: { $0.ts < $1.ts })
            .flatMap { obs -> [WCChartSample] in
                let date = Date(timeIntervalSince1970: obs.ts)
                let wind = obs.ws.moy.value ?? .nan
                let gust = obs.ws.max.value ?? .nan

                var out: [WCChartSample] = []
                if wind.isFinite {
                    out.append(WCChartSample(id: "\(Int(obs.ts))_wind", t: date, value: wind, kind: .wind))
                }
                if gust.isFinite {
                    out.append(WCChartSample(id: "\(Int(obs.ts))_gust", t: date, value: gust, kind: .gust))
                }
                return out
            }

        return ChartResult(latest: latest, samples: samples)
    }

    /// Lightweight latest fetch for map refresh.
    static func fetchLatest(sensorId: String) async throws -> WCWindObservation {
        let result = try await fetchChart(sensorId: sensorId, timeFrame: 12)
        return result.latest
    }

    // MARK: - Flexible decode (backend may wrap arrays)

    private struct ObsArrayWrapper: Decodable {
        let observations: [WCWindObservation]

        init(from decoder: Decoder) throws {
            if let arr = try? [WCWindObservation](from: decoder) {
                observations = arr
                return
            }

            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let arr = try? c.decode([WCWindObservation].self, forKey: .data) {
                observations = arr
                return
            }
            if let arr = try? c.decode([WCWindObservation].self, forKey: .observations) {
                observations = arr
                return
            }
            if let arr = try? c.decode([WCWindObservation].self, forKey: .items) {
                observations = arr
                return
            }

            observations = []
        }

        private enum CodingKeys: String, CodingKey {
            case data
            case observations
            case items
        }
    }

    private static func decodeObservations(from data: Data, decoder: JSONDecoder) throws -> [WCWindObservation] {
        if let arr = try? decoder.decode([WCWindObservation].self, from: data) {
            return arr
        }
        let wrapped = try decoder.decode(ObsArrayWrapper.self, from: data)
        return wrapped.observations
    }
}
