import Foundation
import CoreLocation

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
    case dir
}

struct WCChartSample: Identifiable, Hashable {
    let id: String
    let t: Date
    let value: Double
    let kind: SeriesKind
}
