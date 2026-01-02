
import SwiftUI
import UIKit
import MapKit
import Charts
import Combine

// MARK: - GoWind (carte des vents)
private struct GoWindStation: Decodable {
    let type: String?
    let nom: String?
    let icone: String?
    let now: String?
    let id: String
    let vmaxRaw: String?
    let vmoyRaw: String?
    let ortexte: String?
    let couleur: String?
    let ordegreRaw: String?
    let latValue: Double
    let lonValue: Double
    let mode: String?
    let dern_r: Int?

    // MARK: - Decoding
    enum CodingKeys: String, CodingKey {
        case type, nom, icone, now, id, vmax, vmoy, ortexte, couleur, ordegre, lat, lon, mode, dern_r
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        nom = try c.decodeIfPresent(String.self, forKey: .nom)
        icone = try c.decodeIfPresent(String.self, forKey: .icone)
        now = try c.decodeIfPresent(String.self, forKey: .now)

        // id can be string or number
        if let s = try c.decodeIfPresent(String.self, forKey: .id) {
            id = s
        } else if let n = try c.decodeIfPresent(Int.self, forKey: .id) {
            id = String(n)
        } else {
            id = UUID().uuidString
        }

        // wind values can be string or number
        if let s = try c.decodeIfPresent(String.self, forKey: .vmoy) {
            vmoyRaw = s
        } else if let n = try c.decodeIfPresent(Double.self, forKey: .vmoy) {
            vmoyRaw = String(n)
        } else if let n = try c.decodeIfPresent(Int.self, forKey: .vmoy) {
            vmoyRaw = String(n)
        } else {
            vmoyRaw = nil
        }

        if let s = try c.decodeIfPresent(String.self, forKey: .vmax) {
            vmaxRaw = s
        } else if let n = try c.decodeIfPresent(Double.self, forKey: .vmax) {
            vmaxRaw = String(n)
        } else if let n = try c.decodeIfPresent(Int.self, forKey: .vmax) {
            vmaxRaw = String(n)
        } else {
            vmaxRaw = nil
        }

        ortexte = try c.decodeIfPresent(String.self, forKey: .ortexte)
        couleur = try c.decodeIfPresent(String.self, forKey: .couleur)

        if let s = try c.decodeIfPresent(String.self, forKey: .ordegre) {
            ordegreRaw = s
        } else if let n = try c.decodeIfPresent(Double.self, forKey: .ordegre) {
            ordegreRaw = String(n)
        } else if let n = try c.decodeIfPresent(Int.self, forKey: .ordegre) {
            ordegreRaw = String(n)
        } else {
            ordegreRaw = nil
        }

        // lat/lon can be string or number
        latValue = Self.decodeDouble(c, .lat)
        lonValue = Self.decodeDouble(c, .lon)

        mode = try c.decodeIfPresent(String.self, forKey: .mode)
        dern_r = try c.decodeIfPresent(Int.self, forKey: .dern_r)
    }

    // MARK: - Fallback dictionary init (very tolerant + recursive key search)
    init?(dict d: [String: Any]) {
        // Recursive search for keys anywhere in the JSON object.
        func findValue(in any: Any, keys: Set<String>, maxDepth: Int = 6) -> Any? {
            guard maxDepth > 0 else { return nil }

            if let dict = any as? [String: Any] {
                // Direct hit
                for (k, v) in dict {
                    if keys.contains(k.lowercased()) { return v }
                }
                // Recurse into children
                for (_, v) in dict {
                    if let hit = findValue(in: v, keys: keys, maxDepth: maxDepth - 1) { return hit }
                }
            } else if let arr = any as? [Any] {
                for v in arr {
                    if let hit = findValue(in: v, keys: keys, maxDepth: maxDepth - 1) { return hit }
                }
            }
            return nil
        }

        func asString(_ any: Any?) -> String? {
            guard let any else { return nil }
            if let s = any as? String { return s }
            if let n = any as? NSNumber { return n.stringValue }
            if let i = any as? Int { return String(i) }
            if let d = any as? Double { return String(d) }
            return nil
        }

        func asDouble(_ any: Any?) -> Double? {
            guard let any else { return nil }
            if let d = any as? Double { return d }
            if let n = any as? NSNumber { return n.doubleValue }
            if let i = any as? Int { return Double(i) }
            if let s = any as? String {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { return nil }

                // Extract the first numeric token from the string (handles extra chars like ° ' " N/E/W, etc.)
                var token = ""
                var started = false
                for ch in trimmed {
                    let isAllowed = (ch >= "0" && ch <= "9") || ch == "-" || ch == "." || ch == ","
                    if isAllowed {
                        token.append(ch)
                        started = true
                    } else if started {
                        break
                    }
                }

                let normalized = token.replacingOccurrences(of: ",", with: ".")
                if normalized.isEmpty { return nil }
                return Double(normalized)
            }
            return nil
        }

        func pickString(_ keys: [String]) -> String? {
            for k in keys {
                if let v = asString(findValue(in: d, keys: [k.lowercased()])) {
                    let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { return t }
                }
            }
            return nil
        }

        func pickDouble(_ keys: [String]) -> Double? {
            for k in keys {
                if let v = asDouble(findValue(in: d, keys: [k.lowercased()])) {
                    if v.isFinite { return v }
                }
            }
            return nil
        }

        func pickInt(_ keys: [String]) -> Int? {
            for k in keys {
                if let n = findValue(in: d, keys: [k.lowercased()]) {
                    if let i = n as? Int { return i }
                    if let num = n as? NSNumber { return num.intValue }
                    if let s = n as? String {
                        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let i = Int(t) { return i }
                    }
                }
            }
            return nil
        }

        // Base fields (try root keys first, then recursive)
        type = asString(d["type"]) ?? pickString(["type"])

        // Accept both GoWind + Holfuy items from the same feed
        let rawType = (type ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard rawType.isEmpty || rawType == "gowind" || rawType == "holfuy" else {
            return nil
        }
        nom  = asString(d["nom"])  ?? pickString(["nom", "name", "station", "spot"])
        icone = asString(d["icone"]) ?? pickString(["icone", "icon"])
        now   = asString(d["now"])   ?? pickString(["now", "date", "time", "timestamp"])

        // id can be string/number, sometimes missing → fallback to nom
        let idStr = asString(d["id"]) ?? pickString(["id", "station_id", "uid"]) ?? (nom ?? UUID().uuidString)
        id = idStr

        // wind values (avg / gust)
        vmoyRaw = pickString([
            "vmoy", "ws", "moy", "moyenne", "wind", "wind_avg", "vitesse", "vitesse_moy", "vitesse_moyenne", "speed", "avg"
        ])
        vmaxRaw = pickString([
            "vmax", "gust", "rafale", "wind_gust", "vitesse_max", "vitesse_rafale", "max"
        ])

        ortexte = pickString(["ortexte", "card", "dir_txt", "direction_txt"])
        couleur = pickString(["couleur", "color", "couleur_hex"])
        ordegreRaw = pickString(["ordegre", "dir", "direction", "wd", "bearing", "heading"])

        // coords (often nested) — try direct keys first, then recursive search
        let lat = asDouble(d["lat"]) ?? asDouble(d["latitude"]) ?? asDouble(d["y"]) ?? pickDouble(["lat", "latitude", "y"])
        let lon = asDouble(d["lon"]) ?? asDouble(d["lng"]) ?? asDouble(d["longitude"]) ?? asDouble(d["x"]) ?? pickDouble(["lon", "lng", "longitude", "x"])

        latValue = lat ?? 0
        lonValue = lon ?? 0

        mode = pickString(["mode", "etat", "status"])
        dern_r = pickInt(["dern_r", "age", "age_min", "age_minutes", "last", "last_min"])

        // Sanity checks: accept only plausible coordinates.
        if !(latValue >= -90 && latValue <= 90 && lonValue >= -180 && lonValue <= 180) {
            return nil
        }
        // Only reject the exact (0,0) case.
        if latValue == 0 && lonValue == 0 {
            return nil
        }
    }

    private static func decodeDouble(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double {
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d ?? 0 }
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return Double(i ?? 0) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) {
            return Double((s ?? "0").replacingOccurrences(of: ",", with: ".")) ?? 0
        }
        return 0
    }

    // MARK: - Computed
    private func parse(_ raw: String?) -> Double {
        guard let raw else { return 0 }
        let s = raw.replacingOccurrences(of: ",", with: ".")
        return Double(s) ?? 0
    }

    var wind: Double { parse(vmoyRaw) }
    var gust: Double { parse(vmaxRaw) }
    var dirDeg: Double { parse(ordegreRaw) }

    var coordinate: CLLocationCoordinate2D { .init(latitude: latValue, longitude: lonValue) }
    var isOnline: Bool { (mode ?? "").uppercased() == "ON" }

    /// GoWind IDs are not guaranteed unique across the whole dataset.
    /// Use a composite id so SwiftUI ForEach doesn't collapse duplicates.
    var stableId: String {
        "\(id)-\(String(format: "%.6f", latValue))-\(String(format: "%.6f", lonValue))"
    }
}

@MainActor
private final class GoWindStore: ObservableObject {
    @Published var stations: [GoWindStation] = []
    @Published var lastStatusCode: Int? = nil
    @Published var lastBytes: Int = 0
    @Published var lastError: String? = nil
    @Published var lastTotalItems: Int = 0
    @Published var lastDecodedItems: Int = 0

    func refresh() async {
        guard let url = URL(string: "https://gowind.fr/php/anemo/carte_des_vents.json") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("AnemOuest/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode
            lastStatusCode = status
            lastBytes = data.count
            lastError = nil

            let json = try JSONSerialization.jsonObject(with: data, options: [])

            // Collect candidate station JSON objects (robust: array root OR dict root with embedded arrays)
            var candidates: [Any] = []

            func looksLikeStation(_ obj: Any) -> Bool {
                guard let d0 = obj as? [String: Any] else { return false }

                // Merge common nested containers where coordinates may live
                var d = d0
                let nestedKeys = ["coord", "coords", "position", "pos", "geo", "location", "loc", "station"]
                for nk in nestedKeys {
                    if let nested = d0[nk] as? [String: Any] {
                        for (k, v) in nested { d[k] = v }
                    }
                }

                var hasLat = false
                var hasLon = false
                var hasWind = false

                for k in d.keys {
                    let key = k.lowercased()
                    if key == "lat" || key == "latitude" || key == "y" { hasLat = true }
                    if key == "lon" || key == "lng" || key == "longitude" || key == "x" { hasLon = true }
                    if key == "vmoy" || key == "vmax" || key == "wind" || key == "gust" { hasWind = true }
                }

                // Prefer stations with coords, but keep wind-like objects too and let the tolerant init decide.
                if hasLat && hasLon { return true }
                return hasWind
            }

            if let arr = json as? [Any] {
                // Array root: keep everything and let the tolerant parser decide.
                candidates = arr
            } else if let dict = json as? [String: Any] {
                // Dict root: prefer the largest embedded array that looks like stations
                var bestArray: [Any] = []
                for (_, v) in dict {
                    if let a = v as? [Any] {
                        var filtered: [Any] = []
                        filtered.reserveCapacity(a.count)
                        for item in a {
                            if looksLikeStation(item) { filtered.append(item) }
                        }
                        if filtered.count > bestArray.count {
                            bestArray = filtered
                        }
                    }
                }

                if !bestArray.isEmpty {
                    candidates = bestArray
                } else {
                    // Otherwise, dict values might themselves be station objects
                    let values = Array(dict.values)
                    var tmp: [Any] = []
                    tmp.reserveCapacity(values.count)
                    for item in values {
                        if looksLikeStation(item) { tmp.append(item) }
                    }
                    candidates = tmp
                }

                if candidates.isEmpty {
                    // Debug: show top-level keys once if nothing matched
                    print("GoWind dict root keys:", Array(dict.keys).prefix(20))
                }
            }

            lastTotalItems = candidates.count

            // Decode per-item (tolerant) — do NOT fail all stations if a few are malformed
            var decoded: [GoWindStation] = []
            decoded.reserveCapacity(candidates.count)
            var failed = 0

            for item in candidates {
                // DEBUG: inspect a specific station directly from the live payload
                if let dict = item as? [String: Any] {
                    let rawId = (dict["id"] as? String)
                        ?? (dict["id"] as? NSNumber)?.stringValue
                        ?? String(describing: dict["id"] ?? "")

                    if rawId == "1821" {
                        let latRaw = dict["lat"] ?? dict["latitude"] ?? dict["y"] ?? "<none>"
                        let lonRaw = dict["lon"] ?? dict["lng"] ?? dict["longitude"] ?? dict["x"] ?? "<none>"
                        print("GoWind RAW 1821 lat:", latRaw, "lon:", lonRaw)
                        print("GoWind RAW 1821 keys:", Array(dict.keys).sorted())
                        // Uncomment if you want the full dictionary:
                        // print("GoWind RAW 1821 dict:", dict)
                    }
                }
                // Fallback: try to interpret as dictionary and build a station (recursive tolerant)
                if let dict = item as? [String: Any], let st = GoWindStation(dict: dict) {
                    decoded.append(st)
                } else {
                    failed += 1

                    // Debug a few failures to understand the JSON shape
                    if failed <= 3, let dict = item as? [String: Any] {
                        let id = (dict["id"] as? String) ?? String(describing: dict["id"] ?? "?")
                        let nom = (dict["nom"] as? String) ?? (dict["name"] as? String) ?? "?"
                        let latRaw = dict["lat"] ?? dict["latitude"] ?? dict["y"] ?? "<none>"
                        let lonRaw = dict["lon"] ?? dict["lng"] ?? dict["longitude"] ?? dict["x"] ?? "<none>"
                        print("GoWind failed sample id:", id, "nom:", nom)
                        print("  raw lat:", latRaw)
                        print("  raw lon:", lonRaw)
                        print("  keys:", Array(dict.keys).sorted().prefix(40))
                    }
                }
            }

            stations = decoded
            lastDecodedItems = decoded.count

            print("GoWind status:", status ?? -1, "bytes:", data.count, "total:", candidates.count, "decoded:", decoded.count, "failed:", failed)
            if let first = decoded.first {
                print("GoWind first:", first.id, first.coordinate.latitude, first.coordinate.longitude, "w", first.wind, "g", first.gust)
            }

            let matches1821 = decoded.filter { $0.id == "1821" }
            if !matches1821.isEmpty {
                print("GoWind id 1821 matches:", matches1821.count)
                for m in matches1821.prefix(6) {
                    print("  1821 -> stableId:", m.stableId, "lat:", m.latValue, "lon:", m.lonValue, "w:", m.wind, "g:", m.gust)
                }
            } else {
                print("GoWind id 1821 not decoded (missing coords or rejected)")
            }

            // If nothing decoded, show a snippet to debug quickly
            if decoded.isEmpty {
                let snippet = String(data: data.prefix(220), encoding: .utf8) ?? "<non-utf8>"
                lastError = "Decode empty (status: \(status ?? -1), bytes: \(data.count)) snippet: \(snippet)"
                print("GoWind empty decode. snippet:", snippet)
            }

        } catch {
            lastError = String(describing: error)
            stations = []
            lastTotalItems = 0
            lastDecodedItems = 0
            print("GoWind refresh failed:", error)
        }
    }
}

struct ContentView: View {

    // MARK: - Sensors (sans Holfuy)
    private let sensors: [SensorConfig] = [
        .init(id: "6", name: "Glénan", coordinate: .init(latitude: 47.720000, longitude: -3.990000)),
        .init(id: "29058003", name: "Beg Meil", coordinate: .init(latitude: 47.85442, longitude: -3.97634)),
        .init(id: "29158001", name: "Penmarch", coordinate: .init(latitude: 47.798040, longitude: -4.373896)),
        .init(id: "29214001", name: "Plovan", coordinate: .init(latitude: 47.932433, longitude: -4.392694)),
        .init(id: "7", name: "Pointe de Trévignon", coordinate: .init(latitude: 47.790568, longitude: -3.855443)),

        .init(id: "56069001", name: "Groix", coordinate: .init(latitude: 47.652444, longitude: -3.502139)),
        .init(id: "56009001", name: "Belle-Île", coordinate: .init(latitude: 47.302983, longitude: -3.238389)),
        .init(id: "8", name: "Pornichet", coordinate: .init(latitude: 47.257621, longitude: -2.351409)),
        .init(id: "44184001", name: "Pointe de Chemoulin", coordinate: .init(latitude: 47.233827, longitude: -2.298877)),
        .init(id: "2", name: "St Gildas", coordinate: .init(latitude: 47.133768, longitude: -2.246263)),
        .init(id: "10", name: "Port Navalo", coordinate: .init(latitude: 47.547730, longitude: -2.919029)),
        .init(id: "5", name: "Phare de la Teignouse", coordinate: .init(latitude: 47.453738, longitude: -3.050746)),
        .init(id: "56186003", name: "Quiberon Aérodrome", coordinate: .init(latitude: 47.481116, longitude: -3.102231))
    ]

    // MARK: - State
    @StateObject private var vm = WindViewModel()
    @StateObject private var goWind = GoWindStore()
    @State private var goWindTick = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    @AppStorage("refreshIntervalSeconds") private var refreshIntervalSeconds: Double = 20

    @State private var selected: SensorConfig? = nil
    @State private var timeFrame: Int = 60   // 2h
    @State private var showPanel: Bool = false
    @State private var showChartFull: Bool = false
    @State private var showSettings: Bool = false

    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.6, longitude: -3.6),
            span: MKCoordinateSpan(latitudeDelta: 1.6, longitudeDelta: 2.0)
        )
    )

    // Chart interaction
    @State private var touchX: Date? = nil
    @State private var touchSampleWind: Double? = nil
    @State private var touchSampleGust: Double? = nil

    // MARK: - Animations
    private let panelAnim = Animation.smooth(duration: 0.38)
    private let cameraAnim = Animation.smooth(duration: 0.55)

    var body: some View {
        homeView
            .sheet(isPresented: $showSettings) {
                SettingsView(refreshInterval: $refreshIntervalSeconds)
            }
    }

    private var homeView: some View {
        ZStack(alignment: .top) {
            mapWithSettings
            panelLayer
        }
        .animation(panelAnim, value: showPanel)
        .onAppear {
            vm.startAutoRefresh(
                sensorIds: sensors.map(\.id),
                selectedSensorId: { selected?.id },
                timeFrame: { timeFrame },
                refreshIntervalSeconds: { refreshIntervalSeconds }
            )
            Task { await goWind.refresh() }
        }
        .onDisappear { vm.stopAutoRefresh() }
        .onReceive(goWindTick) { _ in
            Task { await goWind.refresh() }
        }
        // iOS 17+ signature
        .onChange(of: timeFrame) { _, _ in
            guard let selected = selected else { return }
            Task { await vm.loadSelected(sensorId: selected.id, timeFrame: timeFrame) }
        }
        .onChange(of: refreshIntervalSeconds) { _, _ in
            vm.startAutoRefresh(
                sensorIds: sensors.map(\.id),
                selectedSensorId: { selected?.id },
                timeFrame: { timeFrame },
                refreshIntervalSeconds: { refreshIntervalSeconds }
            )
        }
        .sheet(isPresented: $showChartFull) {
            if let selected = selected {
                ChartFullScreen(
                    title: selected.name,
                    latest: vm.latestBySensorId[selected.id],
                    samples: vm.samples,
                    timeFrame: $timeFrame,
                    lastUpdatedAt: vm.lastUpdatedAt,
                    touchX: $touchX,
                    touchWind: $touchSampleWind,
                    touchGust: $touchSampleGust,
                    onClose: {
                        haptic(.light)
                        withAnimation(panelAnim) {
                            showChartFull = false
                        }
                    }
                )
            }
        }
    }

    private var mapWithSettings: AnyView {
        let selectedId = selected?.id
        let latest = vm.latestBySensorId
        let stations = goWind.stations
        let status = goWind.lastStatusCode
        let decoded = goWind.lastDecodedItems
        let total = goWind.lastTotalItems
        let center: CLLocationCoordinate2D = camera.region?.center ?? CLLocationCoordinate2D(latitude: 46.9, longitude: -2.7)

        return AnyView(
            buildMapLayerView(
                center: center,
                selectedId: selectedId,
                latest: latest,
                stations: stations,
                status: status,
                decoded: decoded,
                total: total
            )
        )
    }

    private func buildMapLayerView(
        center: CLLocationCoordinate2D,
        selectedId: String?,
        latest: [String: WCWindObservation],
        stations: [GoWindStation],
        status: Int?,
        decoded: Int,
        total: Int
    ) -> some View {
        MapLayerView(
            camera: $camera,
            cameraCenter: center,
            sensors: sensors,
            selectedId: selectedId,
            latestBySensorId: latest,
            goWindStations: stations,
            goWindStatusCode: status,
            goWindDecoded: decoded,
            goWindTotal: total,
            onTapSensor: { s in
                haptic(.medium)
                select(sensor: s, animated: true)
            },
            onTapSettings: {
                haptic(.light)
                showSettings = true
            },
            onTapScope: {
                withAnimation(.smooth(duration: 0.55)) {
                    camera = .region(
                        MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: 46.9, longitude: -2.7),
                            span: MKCoordinateSpan(latitudeDelta: 3.8, longitudeDelta: 4.8)
                        )
                    )
                }
            }
        )
    }



    private var panelLayer: AnyView {
        AnyView(
            VStack {
                Spacer()
                if showPanel, let selected = selected {
                    BottomPanel(
                        sensorName: selected.name,
                        latest: vm.latestBySensorId[selected.id],
                        samples: vm.samples,
                        timeFrame: $timeFrame,
                        lastUpdatedAt: vm.lastUpdatedAt,
                        hadError: vm.hadRecentError,
                        touchX: $touchX,
                        touchWind: $touchSampleWind,
                        touchGust: $touchSampleGust,
                        onClose: {
                            haptic(.light)
                            withAnimation(panelAnim) {
                                showPanel = false
                                showChartFull = false
                            }
                        },
                        onFullscreen: {
                            haptic(.light)
                            withAnimation(panelAnim) {
                                showChartFull = true
                            }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 10)
                    .padding(.horizontal, 12)
                }
            }
        )
    }


    private func select(sensor: SensorConfig, animated: Bool) {
        withAnimation(panelAnim) {
            selected = sensor
            showPanel = true
            showChartFull = false
        }

        if animated {
            withAnimation(cameraAnim) {
                let span = MKCoordinateSpan(latitudeDelta: 0.55, longitudeDelta: 0.75)
                // Move map center slightly south so the selected marker sits higher on screen (above the bottom panel)
                let yOffset = span.latitudeDelta * 0.22
                let centered = CLLocationCoordinate2D(
                    latitude: sensor.coordinate.latitude - yOffset,
                    longitude: sensor.coordinate.longitude
                )
                camera = .region(MKCoordinateRegion(center: centered, span: span))
            }
        } else {
            let span = MKCoordinateSpan(latitudeDelta: 0.55, longitudeDelta: 0.75)
            let yOffset = span.latitudeDelta * 0.22
            let centered = CLLocationCoordinate2D(
                latitude: sensor.coordinate.latitude - yOffset,
                longitude: sensor.coordinate.longitude
            )
            camera = .region(MKCoordinateRegion(center: centered, span: span))
        }

        Task { await vm.loadSelected(sensorId: sensor.id, timeFrame: timeFrame) }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let g = UIImpactFeedbackGenerator(style: style)
        g.prepare()
        g.impactOccurred()
    }
}


// MARK: - Map layer extracted (helps compiler type-check)

private struct MapLayerView: View {
    @Binding var camera: MapCameraPosition
    let cameraCenter: CLLocationCoordinate2D

    let sensors: [SensorConfig]
    let selectedId: String?
    let latestBySensorId: [String: WCWindObservation]

    let goWindStations: [GoWindStation]
    let goWindStatusCode: Int?
    let goWindDecoded: Int
    let goWindTotal: Int

    let onTapSensor: (SensorConfig) -> Void
    let onTapSettings: () -> Void
    let onTapScope: () -> Void

    private var goWindBadgeText: String {
        let codeText = goWindStatusCode.map(String.init) ?? "—"
        return "GoWind: \(goWindDecoded)/\(goWindTotal) (\(codeText))"
    }

    var body: some View {
        mapView
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) { settingsButton }
            .overlay(alignment: .topLeading) { goWindHUD }
    }

    private var mapView: some View {
        Map(position: $camera) {
            sensorAnnotations()
            goWindAnnotations()
        }
        .mapStyle(.standard)
    }

    @MapContentBuilder
    private func sensorAnnotations() -> some MapContent {
        ForEach(sensors) { s in
            Annotation("", coordinate: s.coordinate, anchor: .center) {
                SensorMarker(
                    name: s.name,
                    latest: latestBySensorId[s.id],
                    isSelected: s.id == selectedId
                )
                .onTapGesture { onTapSensor(s) }
            }
        }
    }

    private var limitedGoWindStations: [GoWindStation] {
        closestStations(to: cameraCenter, from: goWindStations, limit: 650)
    }

    @MapContentBuilder
    private func goWindAnnotations() -> some MapContent {
        ForEach(limitedGoWindStations, id: \.stableId) { st in
            Annotation("", coordinate: st.coordinate, anchor: .center) {
                GoWindMarker(station: st)
            }
        }
    }

    private func closestStations(to center: CLLocationCoordinate2D, from stations: [GoWindStation], limit: Int) -> [GoWindStation] {
        guard !stations.isEmpty else { return [] }
        // Filter obvious invalid coords (extra safety)
        let valid = stations.filter { st in
            let lat = st.coordinate.latitude
            let lon = st.coordinate.longitude
            return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180 && !(lat == 0 && lon == 0)
        }
        // Sort by distance to center and cap
        return valid
            .sorted { a, b in
                haversineKm(center, a.coordinate) < haversineKm(center, b.coordinate)
            }
            .prefix(limit)
            .map { $0 }
    }

    private func haversineKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let r = 6371.0
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let s1 = sin(dLat / 2)
        let s2 = sin(dLon / 2)
        let h = s1 * s1 + cos(lat1) * cos(lat2) * s2 * s2
        return 2 * r * asin(min(1, sqrt(h)))
    }

    private var settingsButton: some View {
        Button(action: onTapSettings) {
            Image(systemName: "gearshape")
                .font(.system(size: 16, weight: .semibold))
                .padding(8)
                .background(.thinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.trailing, 12)
        .padding(.top, 6)
    }

    private var goWindHUD: some View {
        HStack(spacing: 8) {
            Text(goWindBadgeText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))

            Button(action: onTapScope) {
                Image(systemName: "scope")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(8)
                    .background(.thinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.top, 6)
    }
}

// MARK: - Sensor Marker (small arrow + colored numbers)

private struct SensorMarker: View {
    let name: String
    let latest: WCWindObservation?
    let isSelected: Bool

    private var wind: Double? { latest?.ws.moy.value }
    private var gust: Double? { latest?.ws.max.value }
    private var dir: Double?  { latest?.wd.moy.value }

    var body: some View {
        VStack(spacing: 4) {
            CleanArrow(deg: dir ?? 0, isSelected: isSelected)
            CapsulePill(wind: wind, gust: gust, isSelected: isSelected)
        }
    }
}

private struct CapsulePill: View {
    let wind: Double?
    let gust: Double?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(fmt(wind))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(color(wind))

            Text("/")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(fmt(gust))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(color(gust))

            Text("nds")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(isSelected ? 0.16 : 0.10), lineWidth: isSelected ? 1.2 : 0.9)
        )
        .shadow(radius: isSelected ? 5 : 2)
    }

    private func fmt(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int(round(v)))"
    }

    private func color(_ v: Double?) -> Color {
        guard let v else { return .secondary }
        return windScale(v)
    }
}

// MARK: - Arrow (not colored)

private struct CleanArrow: View {
    let deg: Double
    let isSelected: Bool

    var body: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: isSelected ? 16 : 14, weight: .semibold))
            .foregroundStyle(.primary.opacity(isSelected ? 1.0 : 0.9))
            .rotationEffect(.degrees(deg + 180))
            .padding(5)
            .background(
                Circle().fill(.thinMaterial).opacity(isSelected ? 0.55 : 0.35)
            )
            .overlay(
                Circle().strokeBorder(Color.white.opacity(isSelected ? 0.14 : 0.08), lineWidth: 0.8)
            )
            .shadow(radius: isSelected ? 3 : 1)
    }
}

// MARK: - Status Pill (Online / Offline)

private struct StatusPill: View {
    let isOnline: Bool
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isOnline ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)
                .opacity(isOnline ? (pulse ? 0.35 : 0.9) : 0.6)
                .scaleEffect(isOnline ? (pulse ? 0.92 : 1.0) : 1.0)

            Text(isOnline ? "En ligne" : "Hors ligne")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .onAppear {
            guard isOnline else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulse.toggle()
            }
        }
    }
}

// MARK: - Bottom Panel

private struct BottomPanel: View {
    let sensorName: String
    let latest: WCWindObservation?
    let samples: [WCChartSample]
    @Binding var timeFrame: Int
    let lastUpdatedAt: Date?
    let hadError: Bool

    @Binding var touchX: Date?
    @Binding var touchWind: Double?
    @Binding var touchGust: Double?

    let onClose: () -> Void
    let onFullscreen: () -> Void

    var body: some View {
        VStack(spacing: 12) {

            HStack {
                Text(sensorName)
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                Spacer()

                Button(action: onFullscreen) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.plain)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                StatCard(title: "Vent", value: statWind)
                StatCard(title: "Rafales", value: statGust)
                StatCard(title: "Dir", value: statDir)
            }

            Picker("Période", selection: $timeFrame) {
                Text("2 h").tag(60)
                Text("6 h").tag(36)
                Text("24 h").tag(144)
            }
            .pickerStyle(.segmented)

            WindChart(samples: samples.filter { $0.kind == .wind || $0.kind == .gust })
                .frame(height: 220)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { v in
                                            guard let plot = proxy.plotFrame else { return }
                                            let frame = geo[plot]
                                            let x = v.location.x - frame.origin.x
                                            if let date: Date = proxy.value(atX: x) {
                                                touchX = date
                                                updateTouchValues(for: date)
                                            }
                                        }
                                        .onEnded { _ in
                                            touchX = nil
                                            touchWind = nil
                                            touchGust = nil
                                        }
                                )

                            if let t = touchX,
                               let plot = proxy.plotFrame,
                               let xPos = proxy.position(forX: t) {
                                let x = geo[plot].origin.x + xPos

                                Path { p in
                                    p.move(to: CGPoint(x: x, y: geo[plot].minY))
                                    p.addLine(to: CGPoint(x: x, y: geo[plot].maxY))
                                }
                                .stroke(
                                    Color.primary.opacity(0.18),
                                    style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [4, 4])
                                )
                                .allowsHitTesting(false)
                            }
                        }
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let t = touchX {
                        Tooltip(t: t, w: touchWind, g: touchGust)
                            .padding(.top, 6)
                    }
                }

            HStack(spacing: 10) {
                Text(hadError ? "Certaines balises ne répondent pas" : measureText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                StatusPill(isOnline: isOnline)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(radius: 14)
    }

    private var stationDate: Date? {
        guard let ts = latest?.ts else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(Int(ts)))
    }

    private var isOnline: Bool {
        guard let d = stationDate else { return false }
        return Date().timeIntervalSince(d) <= 20 * 60
    }

    private var measureText: String {
        guard let d = stationDate else { return "Mesure —" }
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "Mesure il y a \(s)s" }
        if s < 3600 { return "Mesure il y a \(s/60)m" }
        return "Mesure il y a \(s/3600)h"
    }

    private var statWind: String {
        guard let w = latest?.ws.moy.value else { return "—" }
        return "\(Int(round(w))) nds"
    }

    private var statGust: String {
        guard let g = latest?.ws.max.value else { return "—" }
        return "\(Int(round(g))) nds"
    }

    private var statDir: String {
        guard let d = latest?.wd.moy.value else { return "—" }
        return "\(Int(round(d)))° \(cardinal(from: d))"
    }

    private func cardinal(from deg: Double) -> String {
        let dirs = ["N","NE","E","SE","S","SW","W","NW"]
        let idx = Int((deg + 22.5) / 45.0) & 7
        return dirs[idx]
    }


    private func updateTouchValues(for date: Date) {
        let wind = samples.filter { $0.kind == .wind }
        let gust = samples.filter { $0.kind == .gust }

        touchWind = nearestValue(in: wind, to: date)
        touchGust = nearestValue(in: gust, to: date)

        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.35)
    }

    private func nearestValue(in arr: [WCChartSample], to date: Date) -> Double? {
        guard !arr.isEmpty else { return nil }
        var best: WCChartSample = arr[0]
        var bestDist = abs(arr[0].t.timeIntervalSince(date))
        for s in arr {
            let d = abs(s.t.timeIntervalSince(date))
            if d < bestDist {
                bestDist = d
                best = s
            }
        }
        return best.value
    }
}

// MARK: - Fullscreen Chart

private struct ChartFullScreen: View {
    let title: String
    let latest: WCWindObservation?
    let samples: [WCChartSample]
    @Binding var timeFrame: Int
    let lastUpdatedAt: Date?

    @Binding var touchX: Date?
    @Binding var touchWind: Double?
    @Binding var touchGust: Double?

    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {

                HStack(spacing: 10) {
                    StatCard(title: "Vent", value: statWind)
                    StatCard(title: "Rafales", value: statGust)
                    StatCard(title: "Dir", value: statDir)
                }
                .padding(.horizontal, 14)

                Picker("Période", selection: $timeFrame) {
                    Text("2 h").tag(60)
                    Text("6 h").tag(36)
                    Text("24 h").tag(144)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)

                WindChart(samples: samples.filter { $0.kind == .wind || $0.kind == .gust })
                    .frame(height: 420)
                    .padding(.horizontal, 14)
                    .chartOverlay { proxy in
                        GeometryReader { geo in
                            ZStack(alignment: .topLeading) {
                                Rectangle().fill(.clear).contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { v in
                                                guard let plot = proxy.plotFrame else { return }
                                                let frame = geo[plot]
                                                let x = v.location.x - frame.origin.x
                                                if let date: Date = proxy.value(atX: x) {
                                                    touchX = date
                                                    touchWind = nearestValue(in: samples.filter{$0.kind == .wind}, to: date)
                                                    touchGust = nearestValue(in: samples.filter{$0.kind == .gust}, to: date)
                                                    UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.35)
                                                }
                                            }
                                            .onEnded { _ in
                                                touchX = nil
                                                touchWind = nil
                                                touchGust = nil
                                            }
                                    )

                                if let t = touchX,
                                   let plot = proxy.plotFrame,
                                   let xPos = proxy.position(forX: t) {
                                    let x = geo[plot].origin.x + xPos

                                    Path { p in
                                        p.move(to: CGPoint(x: x, y: geo[plot].minY))
                                        p.addLine(to: CGPoint(x: x, y: geo[plot].maxY))
                                    }
                                    .stroke(
                                        Color.primary.opacity(0.18),
                                        style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [4, 4])
                                    )
                                    .allowsHitTesting(false)
                                }
                            }
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if let t = touchX {
                            Tooltip(t: t, w: touchWind, g: touchGust)
                                .padding(.top, 6)
                                .padding(.leading, 6)
                        }
                    }
                HStack(spacing: 10) {
                    Text(measureText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    StatusPill(isOnline: isOnline)
                }
                .padding(.horizontal, 14)
                Spacer()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
        }
    }

    private var stationDate: Date? {
        guard let ts = latest?.ts else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(Int(ts)))
    }

    private var isOnline: Bool {
        guard let d = stationDate else { return false }
        return Date().timeIntervalSince(d) <= 20 * 60
    }

    private var measureText: String {
        guard let d = stationDate else { return "Mesure —" }
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "Mesure il y a \(s)s" }
        if s < 3600 { return "Mesure il y a \(s/60)m" }
        return "Mesure il y a \(s/3600)h"
    }
    private var statWind: String {
        guard let w = latest?.ws.moy.value else { return "—" }
        return "\(Int(round(w))) nds"
    }
    private var statGust: String {
        guard let g = latest?.ws.max.value else { return "—" }
        return "\(Int(round(g))) nds"
    }
    private var statDir: String {
        guard let d = latest?.wd.moy.value else { return "—" }
        return "\(Int(round(d)))° \(cardinal(from: d))"
    }
    private func cardinal(from deg: Double) -> String {
        let dirs = ["N","NE","E","SE","S","SW","W","NW"]
        let idx = Int((deg + 22.5) / 45.0) & 7
        return dirs[idx]
    }
    private func nearestValue(in arr: [WCChartSample], to date: Date) -> Double? {
        guard !arr.isEmpty else { return nil }
        var best = arr[0]
        var bestDist = abs(arr[0].t.timeIntervalSince(date))
        for s in arr {
            let d = abs(s.t.timeIntervalSince(date))
            if d < bestDist { bestDist = d; best = s }
        }
        return best.value
    }
}

// MARK: - Chart (pro)

private struct WindChart: View {
    let samples: [WCChartSample]

    var body: some View {
        // STRICT: series are identified by the ViewModel ids: "<ts>-w" and "<ts>-g".
        // This prevents any direction values from ever entering the chart.
        let wind = samples
            .filter { $0.id.hasSuffix("-w") }
            .filter { $0.value.isFinite && $0.value >= 0 && $0.value <= 80 }
            .sorted { $0.t < $1.t }

        let gust = samples
            .filter { $0.id.hasSuffix("-g") }
            .filter { $0.value.isFinite && $0.value >= 0 && $0.value <= 80 }
            .sorted { $0.t < $1.t }

        return Chart {
            // Vent moyen — bleu continu
            ForEach(wind) { s in
                LineMark(
                    x: .value("Time", s.t),
                    y: .value("Wind", s.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(by: .value("Series", "Wind"))
                .lineStyle(StrokeStyle(lineWidth: 3.0, lineCap: .round, lineJoin: .round))
                .zIndex(0)
            }

            // Rafales — rouge pointillé
            ForEach(gust) { s in
                LineMark(
                    x: .value("Time", s.t),
                    y: .value("Gust", s.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(by: .value("Series", "Gust"))
                .lineStyle(StrokeStyle(lineWidth: 3.0, lineCap: .round, lineJoin: .round, dash: [6, 4]))
                .zIndex(10)
                .opacity(1)
                PointMark(
                    x: .value("Time", s.t),
                    y: .value("Gust", s.value)
                )
                .symbolSize(12)
                .foregroundStyle(by: .value("Series", "Gust"))
                .opacity(0.35)
            }
        }
        .chartForegroundStyleScale([
            "Wind": .blue,
            "Gust": .red
        ])
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) {
                AxisGridLine(); AxisTick()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) {
                AxisGridLine(); AxisTick(); AxisValueLabel()
            }
        }
        
    }
}
// MARK: - Tooltip

private struct Tooltip: View {
    let t: Date
    let w: Double?
    let g: Double?

    var body: some View {
        HStack(spacing: 10) {
            // Time (HH:mm) only
            Text(t.formatted(.dateTime.hour().minute()))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            // Wind value (colored like map)
            Text(fmt(w))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(color(w))

            Text("/")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            // Gust value (colored like map)
            Text(fmt(g))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(color(g))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func fmt(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int(round(v)))"
    }

    private func color(_ v: Double?) -> Color {
        guard let v else { return .secondary }
        return windScale(v)
    }
}
// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

// MARK: - Wind color scale (approx from your legend)

private func windScale(_ kts: Double) -> Color {
    // Legend (noeuds): <7, 7–10, 11–16, 17–21, 22–27, 28–33, 34–40, 41–47, >48
    switch kts {
    case ..<7:
        // light cyan
        return Color(red: 0.70, green: 0.93, blue: 1.00)
    case ..<11:
        // turquoise
        return Color(red: 0.33, green: 0.85, blue: 0.92)
    case ..<17:
        // green
        return Color(red: 0.35, green: 0.89, blue: 0.52)
    case ..<22:
        // yellow
        return Color(red: 0.97, green: 0.90, blue: 0.33)
    case ..<28:
        // orange
        return Color(red: 0.98, green: 0.67, blue: 0.23)
    case ..<34:
        // red
        return Color(red: 0.95, green: 0.22, blue: 0.26)
    case ..<41:
        // magenta
        return Color(red: 0.83, green: 0.20, blue: 0.67)
    case ..<48:
        // purple
        return Color(red: 0.55, green: 0.24, blue: 0.78)
    default:
        // deep purple
        return Color(red: 0.39, green: 0.24, blue: 0.63)
    }
}

// MARK: - GoWind Marker

private struct GoWindMarker: View {
    let station: GoWindStation

    private var windInt: Int { Int(round(station.wind)) }
    private var gustInt: Int { Int(round(station.gust)) }

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "arrow.up")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary.opacity(station.isOnline ? 0.95 : 0.35))
                // Même convention que CleanArrow
                .rotationEffect(.degrees(station.dirDeg + 180))
                .padding(5)
                .background(
                    Circle().fill(.thinMaterial).opacity(0.30)
                )
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
                )

            HStack(spacing: 5) {
                Text("\(windInt)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(windScale(station.wind))

                Text("/")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Text("\(gustInt)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(windScale(station.gust))

                Text("nds")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.9)
            )
        }
        .allowsHitTesting(false)
    }
}
