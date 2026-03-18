import Foundation

/// Fire-and-forget HEAD requests to Vercel API endpoints at app launch
/// to avoid cold start delays on first real data fetch.
enum APIWarmup {

    // Priorité 1 : Wind France + Météo France (chargent en premier dans l'app)
    private static let priorityEndpoints = [
        "https://api.levent.live/api/windcornouaille",
        "https://api.levent.live/api/stations",
        "https://api.levent.live/api/mf2-stations",
    ]

    // Priorité 2 : Autres sources vent + vagues
    private static let secondaryEndpoints = [
        "https://api.levent.live/api/pioupiou",
        "https://api.levent.live/api/gowind",
        "https://api.levent.live/api/diabox",
        "https://api.levent.live/api/candhis",
    ]

    static func fire() {
        let session = URLSession.shared
        // Envoyer les prioritaires d'abord
        for endpoint in priorityEndpoints + secondaryEndpoints {
            guard let url = URL(string: endpoint) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 8
            request.setValue(AppConstants.API.key, forHTTPHeaderField: "X-Api-Key")
            session.dataTask(with: request) { _, _, _ in }.resume()
        }
        Log.network("[WARMUP] Fired \(priorityEndpoints.count + secondaryEndpoints.count) HEAD requests")
    }
}
