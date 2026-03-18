import Foundation
import CoreLocation
import SwiftUI
import Combine

// MARK: - Unified Wind Station Model

struct WindStation: Identifiable, Equatable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let wind: Double          // knots
    let gust: Double          // knots
    let direction: Double     // degrees
    let isOnline: Bool
    let source: WindSource
    let lastUpdate: Date?

    // Additional metadata (optional)
    var altitude: Int?              // meters
    var stationDescription: String? // description from source
    var picture: String?            // URL to station picture
    var pressure: Double?           // hPa atmospheric pressure
    var temperature: Double?        // °C
    var humidity: Double?           // %

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var stableId: String { "\(source.rawValue)_\(id)" }

    static func == (lhs: WindStation, rhs: WindStation) -> Bool {
        lhs.stableId == rhs.stableId &&
        lhs.wind == rhs.wind &&
        lhs.gust == rhs.gust &&
        lhs.direction == rhs.direction &&
        lhs.isOnline == rhs.isOnline &&
        lhs.lastUpdate == rhs.lastUpdate
    }

    // Explicit init with default values for backward compatibility
    init(
        id: String,
        name: String,
        latitude: Double,
        longitude: Double,
        wind: Double,
        gust: Double,
        direction: Double,
        isOnline: Bool,
        source: WindSource,
        lastUpdate: Date?,
        altitude: Int? = nil,
        stationDescription: String? = nil,
        picture: String? = nil,
        pressure: Double? = nil,
        temperature: Double? = nil,
        humidity: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.wind = wind
        self.gust = gust
        self.direction = direction
        self.isOnline = isOnline
        self.source = source
        self.lastUpdate = lastUpdate
        self.altitude = altitude
        self.stationDescription = stationDescription
        self.picture = picture
        self.pressure = pressure
        self.temperature = temperature
        self.humidity = humidity
    }
}

enum WindSource: String, CaseIterable {
    case pioupiou = "pioupiou"
    case ffvl = "ffvl"
    case holfuy = "holfuy"
    case windguru = "windguru"
    case windsUp = "windsup"
    case meteoFrance = "meteofrance"
    case windCornouaille = "windcornouaille"
    case diabox = "diabox"
    case netatmo = "netatmo"
    case ndbc = "ndbc"

    var displayName: String {
        switch self {
        case .pioupiou: return "Pioupiou"
        case .ffvl: return "FFVL"
        case .holfuy: return "Holfuy"
        case .windguru: return "Windguru"
        case .windsUp: return "WindsUp"
        case .meteoFrance: return "Météo France"
        case .windCornouaille: return "Wind France"
        case .diabox: return "Diabox"
        case .netatmo: return "Netatmo"
        case .ndbc: return "NDBC"
        }
    }

    var color: Color {
        switch self {
        case .pioupiou: return .orange
        case .ffvl: return .red
        case .holfuy: return .green
        case .windguru: return .purple
        case .windsUp: return .cyan
        case .meteoFrance: return .blue
        case .windCornouaille: return .blue
        case .diabox: return .teal
        case .netatmo: return .pink
        case .ndbc: return .indigo
        }
    }
}

// MARK: - France Bounding Box Filter

private func isInFrance(latitude: Double, longitude: Double) -> Bool {
    // Metropolitan France + Corsica bounding box
    // Lat: 41.3 (south Corsica) to 51.1 (north)
    // Lon: -5.2 (Brittany west) to 9.6 (east Corsica)
    let minLat = 41.3
    let maxLat = 51.2
    let minLon = -5.5
    let maxLon = 9.7

    return latitude >= minLat && latitude <= maxLat &&
           longitude >= minLon && longitude <= maxLon
}

/// Extended bounding box for offshore buoys (NDBC, etc.)
private func isNearFrance(latitude: Double, longitude: Double) -> Bool {
    let minLat = 40.0
    let maxLat = 52.0
    let minLon = -12.0
    let maxLon = 10.0

    return latitude >= minLat && latitude <= maxLat &&
           longitude >= minLon && longitude <= maxLon
}

// MARK: - Pioupiou Service

final class PioupiouService {
    static let shared = PioupiouService()
    private init() {}

    private struct Response: Decodable {
        let data: [Station]

        struct Station: Decodable {
            let id: Int
            let meta: Meta
            let location: Location
            let measurements: Measurements

            struct Meta: Decodable {
                let name: String?
            }

            struct Location: Decodable {
                let latitude: Double?
                let longitude: Double?
                let date: String?
                let success: Bool?
            }

            struct Measurements: Decodable {
                let date: String?
                let wind_speed_avg: Double?
                let wind_speed_max: Double?
                let wind_heading: Double?
            }
        }
    }

    func fetchStations() async throws -> [WindStation] {
        guard let url = URL(string: "https://api.pioupiou.fr/v1/live-with-meta/all") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(Response.self, from: data)

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return response.data.compactMap { station -> WindStation? in
            guard let lat = station.location.latitude,
                  let lon = station.location.longitude,
                  lat != 0 && lon != 0,
                  isInFrance(latitude: lat, longitude: lon) else { return nil }

            let windKmh = station.measurements.wind_speed_avg ?? 0
            let gustKmh = station.measurements.wind_speed_max ?? 0

            // Convert km/h to knots
            let windKnots = windKmh * 0.539957
            let gustKnots = gustKmh * 0.539957

            let lastUpdate: Date?
            if let dateStr = station.measurements.date {
                lastUpdate = dateFormatter.date(from: dateStr)
            } else {
                lastUpdate = nil
            }

            // Consider online if updated within 30 minutes
            let isOnline: Bool
            if let update = lastUpdate {
                isOnline = Date().timeIntervalSince(update) < 1800
            } else {
                isOnline = false
            }

            return WindStation(
                id: String(station.id),
                name: station.meta.name ?? "Pioupiou \(station.id)",
                latitude: lat,
                longitude: lon,
                wind: windKnots,
                gust: gustKnots,
                direction: station.measurements.wind_heading ?? 0,
                isOnline: isOnline,
                source: .pioupiou,
                lastUpdate: lastUpdate
            )
        }
    }
}

// MARK: - FFVL Service

final class FFVLService {
    static let shared = FFVLService()
    private init() {}

    private struct Balise: Decodable {
        let idBalise: String?
        let nom: String?
        let lat: String?
        let lon: String?
        let vitesseVentMoy: String?
        let vitesseVentMax: String?
        let directVentMoy: String?
        let date: String?
        let active: String?
    }

    func fetchStations() async throws -> [WindStation] {
        guard let url = URL(string: "https://data.ffvl.fr/json/balises.json") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, _) = try await URLSession.shared.data(for: request)
        let balises = try JSONDecoder().decode([Balise].self, from: data)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        return balises.compactMap { balise -> WindStation? in
            guard let idStr = balise.idBalise,
                  let latStr = balise.lat,
                  let lonStr = balise.lon,
                  let lat = Double(latStr),
                  let lon = Double(lonStr),
                  lat != 0 && lon != 0,
                  isInFrance(latitude: lat, longitude: lon) else { return nil }

            // FFVL provides wind in km/h
            let windKmh = Double(balise.vitesseVentMoy ?? "0") ?? 0
            let gustKmh = Double(balise.vitesseVentMax ?? "0") ?? 0
            let windKnots = windKmh * 0.539957
            let gustKnots = gustKmh * 0.539957

            let direction = Double(balise.directVentMoy ?? "0") ?? 0

            let lastUpdate: Date?
            if let dateStr = balise.date {
                lastUpdate = dateFormatter.date(from: dateStr)
            } else {
                lastUpdate = nil
            }

            let isOnline: Bool
            if balise.active == "0" {
                isOnline = false
            } else if let update = lastUpdate {
                isOnline = Date().timeIntervalSince(update) < 1800
            } else {
                isOnline = true
            }

            return WindStation(
                id: idStr,
                name: balise.nom ?? "FFVL \(idStr)",
                latitude: lat,
                longitude: lon,
                wind: windKnots,
                gust: gustKnots,
                direction: direction,
                isOnline: isOnline,
                source: .ffvl,
                lastUpdate: lastUpdate
            )
        }
    }
}

// MARK: - GoWind Service (for Holfuy & Windguru only)

final class GoWindService {
    static let shared = GoWindService()
    private init() {}

    // Station format in GoWind API
    private struct GoWindStation: Decodable {
        let id: StringOrInt?
        let nom: String?
        let lat: StringOrDouble?
        let lon: StringOrDouble?
        let vmoy: String?
        let vmax: String?
        let ordegre: StringOrDouble?
        let now: String?
        let mode: String?
    }

    // Handle JSON that can be string or number
    private enum StringOrInt: Decodable {
        case string(String)
        case int(Int)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intVal = try? container.decode(Int.self) {
                self = .int(intVal)
            } else if let strVal = try? container.decode(String.self) {
                self = .string(strVal)
            } else {
                throw DecodingError.typeMismatch(StringOrInt.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String or Int"))
            }
        }

        var stringValue: String {
            switch self {
            case .string(let s): return s
            case .int(let i): return String(i)
            }
        }
    }

    private enum StringOrDouble: Decodable {
        case string(String)
        case double(Double)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let doubleVal = try? container.decode(Double.self) {
                self = .double(doubleVal)
            } else if let strVal = try? container.decode(String.self) {
                self = .string(strVal)
            } else {
                throw DecodingError.typeMismatch(StringOrDouble.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String or Double"))
            }
        }

        var doubleValue: Double? {
            switch self {
            case .double(let d): return d
            case .string(let s): return Double(s)
            }
        }
    }

    // Response format: { "holfuy": [...], "windguru": [...], ... }
    private struct GoWindResponse: Decodable {
        let holfuy: [GoWindStation]?
        let windguru: [GoWindStation]?
    }

    func fetchStations(sources: Set<WindSource>) async throws -> [WindStation] {
        guard let url = URL(string: "https://gowind.fr/php/anemo/carte_des_vents.json") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(GoWindResponse.self, from: data)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "fr_FR")

        var stations: [WindStation] = []

        // Process Holfuy stations
        if sources.contains(.holfuy), let holfuyStations = response.holfuy {
            for station in holfuyStations {
                if let ws = parseStation(station, source: .holfuy, dateFormatter: dateFormatter) {
                    stations.append(ws)
                }
            }
        }

        // Process Windguru stations
        let excludedWindguruNames: Set<String> = ["keranguyader"]
        if sources.contains(.windguru), let windguruStations = response.windguru {
            for station in windguruStations {
                if let name = station.nom?.lowercased(), excludedWindguruNames.contains(name) { continue }
                if let ws = parseStation(station, source: .windguru, dateFormatter: dateFormatter) {
                    stations.append(ws)
                }
            }
        }

        return stations
    }

    private func parseStation(_ station: GoWindStation, source: WindSource, dateFormatter: DateFormatter) -> WindStation? {
        guard let id = station.id?.stringValue,
              let lat = station.lat?.doubleValue,
              let lon = station.lon?.doubleValue,
              lat != 0 && lon != 0,
              isInFrance(latitude: lat, longitude: lon) else { return nil }

        // Wind values are in knots as strings
        let wind = Double(station.vmoy ?? "0") ?? 0
        let gust = Double(station.vmax ?? "0") ?? 0
        let direction = station.ordegre?.doubleValue ?? 0

        let lastUpdate: Date?
        if let dateStr = station.now {
            lastUpdate = dateFormatter.date(from: dateStr)
        } else {
            lastUpdate = nil
        }

        let isOnline: Bool
        if station.mode == "OFF" {
            isOnline = false
        } else if let update = lastUpdate {
            isOnline = Date().timeIntervalSince(update) < 1800
        } else {
            isOnline = false
        }

        return WindStation(
            id: id,
            name: station.nom ?? "\(source.displayName) \(id)",
            latitude: lat,
            longitude: lon,
            wind: wind,
            gust: gust,
            direction: direction,
            isOnline: isOnline,
            source: source,
            lastUpdate: lastUpdate
        )
    }
}

// MARK: - Combined Wind Station Manager

@MainActor
final class WindStationManager: ObservableObject {
    static let shared = WindStationManager()

    @Published var stations: [WindStation] = []
    @Published var isLoading: Bool = false
    @Published var lastError: Error? = nil
    @Published var isUsingCache: Bool = false

    /// Current visible map region — used for viewport filtering across all sources
    struct MapBBox {
        let latSW: Double
        let lonSW: Double
        let latNE: Double
        let lonNE: Double

        func contains(lat: Double, lon: Double) -> Bool {
            lat >= latSW && lat <= latNE && lon >= lonSW && lon <= lonNE
        }
    }
    var mapBBox: MapBBox?

    /// Debug info: per-source fetch results from last refresh
    struct SourceDebugInfo {
        let source: WindSource
        let stationCount: Int
        let durationMs: Int
        let status: SourceStatus
        let timestamp: Date
        var apiEndpoint: String?

        enum SourceStatus: String {
            case fresh = "fresh"
            case fallback = "fallback"
            case failed = "failed"
            case disabled = "disabled"
        }
    }
    @Published var sourceDebugInfos: [SourceDebugInfo] = []
    @Published var lastRefreshDate: Date?
    @Published var lastRefreshDurationMs: Int = 0

    private init() {
        // Load cached data immediately on init
        loadFromCache()
    }

    // MARK: - Cache

    func loadFromCache() {
        let cached = CacheManager.shared.loadStations()
        if !cached.isEmpty {
            stations = cached
            isUsingCache = true
        }
    }

    func refresh(sources: Set<WindSource>, userLocation: CLLocationCoordinate2D? = nil) async {
        let refreshStart = Date()
        isLoading = true
        defer { isLoading = false }
        lastError = nil
        isUsingCache = false  // We're fetching fresh data

        var allStations: [WindStation] = []
        let previousStations = self.stations
        var debugInfos: [SourceDebugInfo] = []

        // Phase 1 : Sources prioritaires (Wind France + Météo France) — affichage immédiat
        await withTaskGroup(of: (String, [WindStation], Int).self) { group in
            // WindCornouaille (Wind France)
            group.addTask {
                let t = Date()
                do {
                    let vcStations = try await WindService.fetchAllStations()
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let fallbackFormatter = ISO8601DateFormatter()

                    let r = vcStations.map { s in
                        let lastUpdate = formatter.date(from: s.ts) ?? fallbackFormatter.date(from: s.ts)
                        return WindStation(
                            id: s.id,
                            name: s.name,
                            latitude: s.lat,
                            longitude: s.lon,
                            wind: s.wind,
                            gust: s.gust,
                            direction: s.direction,
                            isOnline: s.isOnline,
                            source: .windCornouaille,
                            lastUpdate: lastUpdate
                        )
                    }
                    let ms = Int(Date().timeIntervalSince(t) * 1000)
                    Log.network("[TIMING] WindCornouaille: \(r.count) stations in \(ms)ms")
                    return ("windcornouaille", r, ms)
                } catch {
                    Log.network("WindCornouaille Vercel fetch failed: \(error)")
                    return ("windcornouaille", previousStations.filter { $0.source == .windCornouaille }, Int(Date().timeIntervalSince(t) * 1000))
                }
            }

            // Météo France (API 1 + API 2 en parallèle)
            if sources.contains(.meteoFrance) {
                group.addTask {
                    let t = Date()
                    let r = await MeteoFranceService.shared.fetchAllStationsFromVercel()
                    let ms = Int(Date().timeIntervalSince(t) * 1000)
                    Log.network("[TIMING] MeteoFrance: \(r.count) stations in \(ms)ms")
                    return ("meteofrance", r, ms)
                }
            }

            for await entry in group {
                let (source, result, ms) = entry
                allStations.append(contentsOf: result)
                let deduped = deduplicateStations(allStations)
                stations = sortByProximity(deduped, to: userLocation)
                Log.network("⏱ PHASE1 \(source): \(result.count) stations — \(ms)ms")

                if let ws = WindSource(rawValue: source) {
                    let endpoint: String = switch ws {
                    case .windCornouaille: "/api/windcornouaille"
                    case .meteoFrance: "/api/meteofrance"
                    default: ""
                    }
                    debugInfos.append(SourceDebugInfo(
                        source: ws,
                        stationCount: result.count,
                        durationMs: ms,
                        status: result.isEmpty ? .failed : .fresh,
                        timestamp: Date(),
                        apiEndpoint: endpoint.isEmpty ? nil : endpoint
                    ))
                }
            }
        }

        let phase1Ms = Int(Date().timeIntervalSince(refreshStart) * 1000)
        Log.network("━━━ Phase 1 done: \(allStations.count) stations in \(phase1Ms)ms ━━━")

        // Phase 2 : Sources secondaires (en parallèle)
        await withTaskGroup(of: (String, [WindStation], Int).self) { group in
            if sources.contains(.pioupiou) {
                group.addTask {
                    let t = Date()
                    let r = await PioupiouVercelService.shared.fetchStationsFromVercel()
                    let ms = Int(Date().timeIntervalSince(t) * 1000)
                    Log.network("[TIMING] Pioupiou: \(r.count) stations in \(ms)ms")
                    return ("pioupiou", r, ms)
                }
            }

            if sources.contains(.ffvl) {
                group.addTask {
                    let t = Date()
                    do {
                        let r = try await FFVLService.shared.fetchStations()
                        let ms = Int(Date().timeIntervalSince(t) * 1000)
                        Log.network("[TIMING] FFVL: \(r.count) stations in \(ms)ms")
                        return ("ffvl", r, ms)
                    } catch {
                        Log.network("FFVL error: \(error)")
                        return ("ffvl", [], Int(Date().timeIntervalSince(t) * 1000))
                    }
                }
            }

            if sources.contains(.holfuy) || sources.contains(.windguru) {
                let wantHolfuy = sources.contains(.holfuy)
                let wantWindguru = sources.contains(.windguru)
                group.addTask {
                    let t = Date()
                    let gowindStations = await GoWindVercelService.shared.fetchStationsFromVercel()
                    var r: [WindStation] = []
                    if wantHolfuy {
                        r.append(contentsOf: gowindStations.filter { $0.source == .holfuy })
                    }
                    if wantWindguru {
                        r.append(contentsOf: gowindStations.filter { $0.source == .windguru })
                    }
                    let ms = Int(Date().timeIntervalSince(t) * 1000)
                    Log.network("[TIMING] GoWind: \(r.count) stations in \(ms)ms")
                    return ("gowind", r, ms)
                }
            }

            if sources.contains(.windsUp) {
                group.addTask {
                    let t = Date()
                    let r = await WindsUpService.shared.fetchWindStations()
                    let ms = Int(Date().timeIntervalSince(t) * 1000)
                    Log.network("[TIMING] WindsUp: \(r.count) stations in \(ms)ms")
                    return ("windsup", r, ms)
                }
            }

            if sources.contains(.diabox) {
                group.addTask {
                    let t = Date()
                    let r = await DiaboxService.shared.fetchStationsFromVercel()
                    let ms = Int(Date().timeIntervalSince(t) * 1000)
                    Log.network("[TIMING] Diabox: \(r.count) stations in \(ms)ms")
                    return ("diabox", r, ms)
                }
            }

            if sources.contains(.netatmo) {
                group.addTask {
                    let t = Date()
                    let r = await NetatmoService.shared.fetchStationsFromVercel()
                    let ms = Int(Date().timeIntervalSince(t) * 1000)
                    Log.network("[TIMING] Netatmo: \(r.count) stations in \(ms)ms")
                    return ("netatmo", r, ms)
                }
            }

            if sources.contains(.ndbc) {
                group.addTask {
                    let t = Date()
                    let r = await NDBCService.shared.fetchStationsFromVercel()
                    let ms = Int(Date().timeIntervalSince(t) * 1000)
                    Log.network("[TIMING] NDBC: \(r.count) stations in \(ms)ms")
                    return ("ndbc", r, ms)
                }
            }

            for await entry in group {
                let (source, result, ms) = entry
                allStations.append(contentsOf: result)
                Log.network("⏱ PHASE2 \(source): \(result.count) stations — \(ms)ms")

                // Map gowind to individual sources
                if source == "gowind" {
                    let holfuyCount = result.filter { $0.source == .holfuy }.count
                    let windguruCount = result.filter { $0.source == .windguru }.count
                    if sources.contains(.holfuy) {
                        debugInfos.append(SourceDebugInfo(source: .holfuy, stationCount: holfuyCount, durationMs: ms, status: holfuyCount > 0 ? .fresh : .failed, timestamp: Date(), apiEndpoint: "/api/gowind"))
                    }
                    if sources.contains(.windguru) {
                        debugInfos.append(SourceDebugInfo(source: .windguru, stationCount: windguruCount, durationMs: ms, status: windguruCount > 0 ? .fresh : .failed, timestamp: Date(), apiEndpoint: "/api/gowind"))
                    }
                } else if let ws = WindSource(rawValue: source) {
                    let endpoint: String? = switch ws {
                    case .pioupiou: "/api/pioupiou"
                    case .windsUp: "winds-up.com (direct)"
                    case .diabox: "/api/diabox"
                    case .netatmo: "/api/netatmo"
                    case .ndbc: "/api/ndbc"
                    default: nil
                    }
                    debugInfos.append(SourceDebugInfo(source: ws, stationCount: result.count, durationMs: ms, status: result.isEmpty ? .failed : .fresh, timestamp: Date(), apiEndpoint: endpoint))
                }
            }
        }

        let totalMs = Int(Date().timeIntervalSince(refreshStart) * 1000)

        // Récap par source
        var sourceCounts: [String: Int] = [:]
        for s in allStations { sourceCounts[s.source.rawValue, default: 0] += 1 }
        let summary = sourceCounts.sorted(by: { $0.key < $1.key }).map { "\($0.key): \($0.value)" }.joined(separator: " | ")
        Log.network("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        Log.network("📊 REFRESH DONE — \(allStations.count) stations total in \(totalMs)ms")
        Log.network("📊 \(summary)")
        Log.network("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // --- Per-station grace: keep individual stations that disappeared ---
        // If a source returned results but some individual stations are missing
        // compared to the previous refresh, keep them for one cycle (grace period)
        let freshStableIds = Set(allStations.map(\.stableId))
        let freshSourcesWithResults = Set(allStations.map(\.source))
        var graceStations: [WindStation] = []
        for prev in previousStations {
            // Only keep if: source DID return results (not a full failure)
            // but this specific station is missing
            guard freshSourcesWithResults.contains(prev.source),
                  !freshStableIds.contains(prev.stableId),
                  prev.isOnline else { continue }
            // Keep it if data is less than 10 minutes old
            if let lastUpdate = prev.lastUpdate,
               Date().timeIntervalSince(lastUpdate) < 600 {
                graceStations.append(prev)
            }
        }
        if !graceStations.isEmpty {
            allStations.append(contentsOf: graceStations)
            Log.network("🔄 Grace: kept \(graceStations.count) stations that disappeared from API (\(graceStations.map(\.name).joined(separator: ", ")))")
        }

        // For sources that returned no results (e.g. network failure),
        // keep previously cached stations for those sources
        let freshSources = freshSourcesWithResults
        let previousSources = Set(previousStations.map(\.source))
        // Only consider sources that actually had cached stations before
        let missingSources = previousSources.subtracting(freshSources)
        var usedFallback = false
        if !missingSources.isEmpty {
            let fallbackStations = previousStations.filter { missingSources.contains($0.source) }
            if !fallbackStations.isEmpty {
                allStations.append(contentsOf: fallbackStations)
                usedFallback = true
                Log.network("Kept \(fallbackStations.count) cached stations for offline sources: \(missingSources.map(\.rawValue))")

                // Mark fallback sources in debug
                for missingSource in missingSources {
                    let count = fallbackStations.filter { $0.source == missingSource }.count
                    debugInfos.append(SourceDebugInfo(source: missingSource, stationCount: count, durationMs: 0, status: .fallback, timestamp: Date()))
                }
            }
        }

        // Add disabled sources
        for source in WindSource.allCases where !sources.contains(source) {
            debugInfos.append(SourceDebugInfo(source: source, stationCount: 0, durationMs: 0, status: .disabled, timestamp: Date()))
        }

        // Save debug info
        sourceDebugInfos = debugInfos
        lastRefreshDate = Date()
        lastRefreshDurationMs = totalMs

        // Save to cache if we got data (fresh or fallback)
        if !allStations.isEmpty {
            let deduplicated = sortByProximity(deduplicateStations(allStations), to: userLocation)
            stations = deduplicated

            // Only overwrite cache if we got fresh network data (not just fallback)
            if !usedFallback || freshSources.count > 1 {
                CacheManager.shared.saveStations(deduplicated)
            }

            // Only flag cache if we actually used fallback data
            if usedFallback {
                isUsingCache = true
            }

            // Compare with stored forecasts for accuracy tracking
            for station in deduplicated where station.isOnline {
                ForecastAccuracyService.shared.compareWithActual(
                    stationId: station.stableId,
                    latitude: station.latitude,
                    longitude: station.longitude,
                    actualWind: station.wind,
                    actualGust: station.gust,
                    actualDirection: station.direction
                )
            }
        } else if stations.isEmpty {
            // No fresh data AND no cached data - stay with empty
            isUsingCache = false
        } else {
            // No fresh data but we have cached data - indicate cache usage
            isUsingCache = true
        }

        // Track refresh performance
        let durationMs = Int(Date().timeIntervalSince(refreshStart) * 1000)
        Analytics.refreshCompleted(durationMs: durationMs, stationCount: stations.count, fromCache: isUsingCache)
    }

    // MARK: - Holfuy Real-time Update (background, after initial load)

    /// Fetches direct Holfuy data and updates stations in-place for more real-time values + temperature
    func refreshHolfuyDirect(userLocation: CLLocationCoordinate2D? = nil) async {
        let holfuyStations = stations.filter { $0.source == .holfuy }
        guard !holfuyStations.isEmpty else { return }

        let stationIds = holfuyStations.map { $0.id }
        let latestData = await HolfuyHistoryService.shared.fetchLatestDataBatch(stationIds: stationIds)
        guard !latestData.isEmpty else { return }

        // Update stations in-place
        stations = stations.map { station in
            guard station.source == .holfuy, let obs = latestData[station.id] else { return station }
            return WindStation(
                id: station.id,
                name: station.name,
                latitude: station.latitude,
                longitude: station.longitude,
                wind: obs.windSpeed,
                gust: obs.gustSpeed,
                direction: obs.direction,
                isOnline: Date().timeIntervalSince(obs.timestamp) < 3600,
                source: .holfuy,
                lastUpdate: obs.timestamp,
                temperature: obs.temperature
            )
        }
        stations = sortByProximity(stations, to: userLocation)
    }

    // MARK: - Proximity Sorting

    private func sortByProximity(_ stations: [WindStation], to location: CLLocationCoordinate2D?) -> [WindStation] {
        guard let loc = location else { return stations }
        // Use squared distance (no sqrt needed for sorting)
        let refLat = loc.latitude
        let refLon = loc.longitude
        return stations.sorted {
            let dLat0 = $0.latitude - refLat
            let dLon0 = $0.longitude - refLon
            let dLat1 = $1.latitude - refLat
            let dLon1 = $1.longitude - refLon
            return (dLat0 * dLat0 + dLon0 * dLon0) < (dLat1 * dLat1 + dLon1 * dLon1)
        }
    }

    // MARK: - Deduplication

    /// Remove duplicate stations at the same location (within ~200m)
    /// Keeps the best station based on: online status, recency, source priority
    private func deduplicateStations(_ stations: [WindStation]) -> [WindStation] {
        guard !stations.isEmpty else { return [] }

        // Grid-based dedup: O(n) instead of O(n²)
        // Cell size ~200m in degrees
        let cellSize: Double = 0.002
        var grid: [String: [WindStation]] = [:]

        for station in stations {
            let key = "\(Int(station.latitude / cellSize)),\(Int(station.longitude / cellSize))"
            grid[key, default: []].append(station)
        }

        return grid.values.map { pickBestStation(from: $0) }
    }

    /// Pick the best station from a group of duplicates
    private func pickBestStation(from group: [WindStation]) -> WindStation {
        guard group.count > 1 else { return group[0] }

        // Source priority (higher = better)
        let sourcePriority: [WindSource: Int] = [
            .windCornouaille: 7,
            .meteoFrance: 6,
            .windsUp: 5,
            .holfuy: 4,
            .windguru: 3,
            .ffvl: 2,
            .pioupiou: 1,
            .diabox: 1,
            .netatmo: 0,
            .ndbc: 5
        ]

        return group.max { a, b in
            // Prefer online stations
            if a.isOnline != b.isOnline {
                return !a.isOnline
            }
            // Prefer more recent data
            if let aDate = a.lastUpdate, let bDate = b.lastUpdate {
                if abs(aDate.timeIntervalSince(bDate)) > 60 {
                    return aDate < bDate
                }
            }
            // Prefer higher priority source
            let aPriority = sourcePriority[a.source] ?? 0
            let bPriority = sourcePriority[b.source] ?? 0
            return aPriority < bPriority
        } ?? group[0]
    }
}
