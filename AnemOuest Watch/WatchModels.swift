import Foundation
import SwiftUI
import CoreLocation

// MARK: - Wind Station

struct WatchStation: Codable, Identifiable, Equatable {
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

    var windInt: Int { Int(wind) }
    var gustInt: Int { Int(gust) }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var cardinalDirection: String {
        let dirs = ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
        let i = Int((direction + 22.5).truncatingRemainder(dividingBy: 360) / 45)
        return dirs[max(0, min(i, 7))]
    }

    var timeAgo: String {
        guard let d = lastUpdate else { return "" }
        let s = Int(-d.timeIntervalSinceNow)
        if s < 60 { return "a l'instant" }
        if s < 3600 { return "il y a \(s / 60) min" }
        if s < 86400 { return "il y a \(s / 3600)h" }
        return "il y a \(s / 86400)j"
    }

    var windColor: Color { Self.color(for: wind) }
    var gustColor: Color { Self.color(for: gust) }

    static func color(for knots: Double) -> Color {
        switch knots {
        case ..<7:  return Color(red: 0.70, green: 0.93, blue: 1.00)
        case ..<11: return Color(red: 0.33, green: 0.85, blue: 0.92)
        case ..<17: return Color(red: 0.35, green: 0.89, blue: 0.52)
        case ..<22: return Color(red: 0.97, green: 0.90, blue: 0.33)
        case ..<28: return Color(red: 0.98, green: 0.67, blue: 0.23)
        case ..<34: return Color(red: 0.95, green: 0.22, blue: 0.26)
        case ..<41: return Color(red: 0.83, green: 0.20, blue: 0.67)
        case ..<48: return Color(red: 0.55, green: 0.24, blue: 0.78)
        default:    return Color(red: 0.39, green: 0.24, blue: 0.63)
        }
    }

    var sourceLabel: String {
        switch source.lowercased() {
        case "windcornouaille", "wind france": return "Wind France"
        case "meteofrance", "meteo france", "météo france": return "Météo France"
        case "pioupiou": return "Pioupiou"
        case "holfuy": return "Holfuy"
        case "windguru": return "Windguru"
        case "diabox": return "Diabox"
        case "ffvl": return "FFVL"
        default: return source
        }
    }
}

// MARK: - Wave Buoy

struct WatchBuoy: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let hm0: Double?        // wave height (m)
    let tp: Double?         // peak period (s)
    let direction: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var heightText: String {
        guard let h = hm0 else { return "--" }
        return String(format: "%.1fm", h)
    }

    var periodText: String {
        guard let t = tp else { return "--" }
        return "\(Int(t))s"
    }

    var waveColor: Color {
        guard let h = hm0 else { return .gray }
        switch h {
        case ..<0.5: return Color(red: 0.58, green: 0.77, blue: 0.99)
        case ..<1.0: return Color(red: 0.37, green: 0.73, blue: 0.98)
        case ..<1.5: return Color(red: 0.20, green: 0.65, blue: 0.33)
        case ..<2.0: return Color(red: 0.97, green: 0.80, blue: 0.17)
        case ..<3.0: return Color(red: 0.98, green: 0.55, blue: 0.24)
        case ..<4.0: return Color(red: 0.93, green: 0.26, blue: 0.26)
        default:     return Color(red: 0.66, green: 0.33, blue: 0.97)
        }
    }
}

// MARK: - Tide

struct WatchTide: Codable, Identifiable, Equatable {
    var id: String { "\(date)_\(time)_\(type)" }
    let type: String        // "high" ou "low"
    let date: String
    let time: String
    let datetime: String
    let height: Double
    let coefficient: Int?

    var isHigh: Bool { type == "high" }

    var localTime: String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        guard let d = fmt.date(from: datetime) else { return time }
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: d)
    }

    var heightText: String {
        String(format: "%.1fm", height)
    }

    var parsedDate: Date? {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.date(from: datetime)
    }
}

struct WatchTideData: Codable {
    let port: WatchTidePort
    let tides: [WatchTide]
    let todayCoefficient: Int?
    let nextHighTide: WatchNextTide?
    let nextLowTide: WatchNextTide?
}

struct WatchTidePort: Codable {
    let name: String
    let cst: String
}

struct WatchNextTide: Codable {
    let time: String
    let height: Double
    let coefficient: Int?

    var localTime: String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        guard let d = fmt.date(from: time) ?? fallback.date(from: time) else { return "--:--" }
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: d)
    }
}

// MARK: - API Response (for direct fetch)

struct WatchAPIStationsResponse: Codable {
    let stations: [WatchAPIStation]
    let cached: Bool
}

struct WatchAPIStation: Codable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
    let wind: Double
    let gust: Double
    let direction: Double
    let isOnline: Bool
    let ts: String?
    let source: String?

    func toStation(defaultSource: String) -> WatchStation {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        let date = ts.flatMap { fmt.date(from: $0) ?? fallback.date(from: $0) }
        let src = source ?? defaultSource
        return WatchStation(
            id: "\(src)_\(id)", name: name, source: src,
            wind: wind, gust: gust, direction: direction,
            isOnline: isOnline, lastUpdate: date,
            latitude: lat, longitude: lon
        )
    }
}
