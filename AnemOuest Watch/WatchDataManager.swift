import Foundation
import Combine
import WatchConnectivity

// MARK: - Data Manager

@MainActor
final class WatchDataManager: ObservableObject {
    @Published var favorites: [WatchStation] = []
    @Published var isReachable: Bool = false
    @Published var lastSync: Date?

    @Published var allStations: [WatchStation] = []
    @Published var buoys: [WatchBuoy] = []
    @Published var isLoadingStations: Bool = false

    @Published var tideData: WatchTideData?
    @Published var isLoadingTides: Bool = false
    @Published var isLoadingFavorites: Bool = false

    private let api = "https://api.levent.live/api"
    private let apiKey = "lv_R3POazDkm6rvLC5NKFNeTOwEu2oDnoN5"
    private var sessionDelegate: WatchSessionDelegate?

    init() {
        loadCache()
        if WCSession.isSupported() {
            sessionDelegate = WatchSessionDelegate(manager: self)
        }
    }

    func requestFavorites() {
        sessionDelegate?.requestFavorites()
    }

    func handleiPhoneData(_ data: [String: Any]) {
        guard let stationsData = data["stations"] as? Data,
              let decoded = try? JSONDecoder().decode([WatchStation].self, from: stationsData) else {
            return
        }
        favorites = decoded
        lastSync = Date()
        if let encoded = try? JSONEncoder().encode(decoded) {
            UserDefaults.standard.set(encoded, forKey: "favCache")
            UserDefaults.standard.set(Date(), forKey: "favSync")
        }
    }

    // MARK: - Fetch favorites directly from API (fallback when iPhone not connected)

    func fetchFavoritesFromAPI() async {
        isLoadingFavorites = true
        defer { isLoadingFavorites = false }

        // Load top Brittany stations as default favorites
        async let wc = fetchAPI("\(api)/windcornouaille", source: "windcornouaille")
        async let mf = fetchAPI("\(api)/stations", source: "meteofrance")
        let results = await wc + mf
        let deduped = deduplicate(results)

        // Show first 6 online stations as "favorites"
        let online = deduped.filter(\.isOnline).prefix(6)
        if !online.isEmpty {
            favorites = Array(online)
            lastSync = Date()
        }
    }

    // MARK: - Fetch stations

    func fetchStationsForMap() async {
        isLoadingStations = true

        async let wc = fetchAPI("\(api)/windcornouaille", source: "windcornouaille")
        async let mf = fetchAPI("\(api)/stations", source: "meteofrance")
        let results = await wc + mf
        if !results.isEmpty { allStations = deduplicate(results) }

        async let piou = fetchAPI("\(api)/pioupiou", source: "pioupiou")
        async let gowind = fetchAPI("\(api)/gowind", source: "gowind")
        let more = await piou + gowind
        if !more.isEmpty { allStations = deduplicate(allStations + more) }

        isLoadingStations = false
    }

    // MARK: - Fetch buoys

    func fetchBuoys() async {
        guard let url = URL(string: "\(api)/candhis") else { return }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 12
            req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
            let (data, _) = try await URLSession.shared.data(for: req)

            struct BuoyResponse: Codable { let buoys: [APIBuoy] }
            struct APIBuoy: Codable {
                let id: String; let name: String
                let lat: Double; let lon: Double
                let hm0: Double?; let tp: Double?; let direction: Double?
            }

            let response = try JSONDecoder().decode(BuoyResponse.self, from: data)
            buoys = response.buoys.map { b in
                WatchBuoy(id: b.id, name: b.name, latitude: b.lat, longitude: b.lon,
                          hm0: b.hm0, tp: b.tp, direction: b.direction)
            }
        } catch {
            WatchLog.error("Buoys: \(error.localizedDescription)")
        }
    }

    // MARK: - Fetch tides

    func fetchTides(port: String = "BREST") async {
        isLoadingTides = true
        defer { isLoadingTides = false }

        guard let url = URL(string: "\(api)/tide?port=\(port)&duration=3") else { return }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 10
            req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
            let (data, _) = try await URLSession.shared.data(for: req)
            let decoded = try JSONDecoder().decode(WatchTideData.self, from: data)
            tideData = decoded
            if let encoded = try? JSONEncoder().encode(decoded) {
                UserDefaults.standard.set(encoded, forKey: "tideCache")
            }
        } catch {
            WatchLog.error("Tides: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    nonisolated private func fetchAPI(_ endpoint: String, source: String) async -> [WatchStation] {
        guard let url = URL(string: endpoint) else { return [] }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 10
            req.setValue("lv_R3POazDkm6rvLC5NKFNeTOwEu2oDnoN5", forHTTPHeaderField: "X-Api-Key")
            let (data, _) = try await URLSession.shared.data(for: req)
            let response = try JSONDecoder().decode(WatchAPIStationsResponse.self, from: data)
            return response.stations.map { $0.toStation(defaultSource: source) }
        } catch {
            return []
        }
    }

    private func deduplicate(_ stations: [WatchStation]) -> [WatchStation] {
        var seen = Set<String>()
        return stations.filter { seen.insert($0.id).inserted }
    }

    private func loadCache() {
        if let data = UserDefaults.standard.data(forKey: "favCache"),
           let cached = try? JSONDecoder().decode([WatchStation].self, from: data) {
            favorites = cached
            lastSync = UserDefaults.standard.object(forKey: "favSync") as? Date
        }
        if let data = UserDefaults.standard.data(forKey: "tideCache"),
           let cached = try? JSONDecoder().decode(WatchTideData.self, from: data) {
            tideData = cached
        }
    }
}

// MARK: - WCSession Delegate

nonisolated(unsafe) final class WatchSessionDelegate: NSObject, WCSessionDelegate, @unchecked Sendable {
    private weak var manager: WatchDataManager?

    init(manager: WatchDataManager) {
        self.manager = manager
        super.init()
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func requestFavorites() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["request": "favorites"], replyHandler: { [weak self] response in
            guard let mgr = self?.manager else { return }
            Task { @MainActor in mgr.handleiPhoneData(response) }
        }, errorHandler: { _ in })
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        guard let mgr = manager else { return }
        Task { @MainActor in
            mgr.isReachable = session.isReachable
            if session.isReachable { mgr.requestFavorites() }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard let mgr = manager else { return }
        Task { @MainActor in
            mgr.isReachable = session.isReachable
            if session.isReachable { mgr.requestFavorites() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext ctx: [String: Any]) {
        guard let mgr = manager else { return }
        Task { @MainActor in mgr.handleiPhoneData(ctx) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo info: [String: Any]) {
        guard let mgr = manager else { return }
        Task { @MainActor in mgr.handleiPhoneData(info) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let mgr = manager else { return }
        Task { @MainActor in
            mgr.handleiPhoneData(message)
            replyHandler([:])
        }
    }
}
