import Foundation
import CoreLocation
import Combine

// MARK: - Webcam Model

struct Webcam: Identifiable, Codable {
    let id: String
    let name: String
    let location: String
    let region: String?
    let latitude: Double
    let longitude: Double
    let imageUrl: String
    let streamUrl: String?
    let source: String
    let refreshInterval: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Webcam Service

final class WebcamService: ObservableObject {
    static let shared = WebcamService()

    @Published var webcams: [Webcam] = []
    @Published var isLoading = false

    private init() {
        Task {
            await loadWebcams()
        }
    }

    func loadWebcams() async {
        await MainActor.run { isLoading = true }

        // Fetch from our Vercel API that proxies webcam images
        let urlString = "https://api.levent.live/api/webcams"

        guard let url = URL(string: urlString) else {
            await MainActor.run {
                self.webcams = Self.fallbackWebcams
                self.isLoading = false
            }
            return
        }

        do {
            let request = AppConstants.apiRequest(url: url)
            let (data, _) = try await URLSession.shared.data(for: request)
            let fetchedWebcams = try JSONDecoder().decode([Webcam].self, from: data)

            await MainActor.run {
                self.webcams = fetchedWebcams.isEmpty ? Self.fallbackWebcams : fetchedWebcams
                self.isLoading = false
            }

            // Prefetch thumbnails for first webcams
            if !fetchedWebcams.isEmpty {
                WebcamImageCache.shared.prefetchImages(for: fetchedWebcams)
            }
        } catch {
            Log.error("Failed to fetch webcams: \(error)")
            await MainActor.run {
                self.webcams = Self.fallbackWebcams
                self.isLoading = false
            }
        }
    }

    func refresh() async {
        await loadWebcams()
    }

    // Get webcams near a coordinate
    func webcamsNear(coordinate: CLLocationCoordinate2D, radiusKm: Double = 50) -> [Webcam] {
        let userLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        return webcams.filter { webcam in
            let webcamLocation = CLLocation(latitude: webcam.latitude, longitude: webcam.longitude)
            let distance = userLocation.distance(from: webcamLocation) / 1000
            return distance <= radiusKm
        }.sorted { webcam1, webcam2 in
            let loc1 = CLLocation(latitude: webcam1.latitude, longitude: webcam1.longitude)
            let loc2 = CLLocation(latitude: webcam2.latitude, longitude: webcam2.longitude)
            return userLocation.distance(from: loc1) < userLocation.distance(from: loc2)
        }
    }

    // Get webcam by ID
    func webcam(byId id: String) -> Webcam? {
        webcams.first { $0.id == id }
    }

    // Get fresh image URL for a webcam (uses our proxy APIs)
    func freshImageUrl(for webcam: Webcam) -> String {
        // The imageUrl from API already points to our proxy
        return webcam.imageUrl
    }

    // Get thumbnail URL (400px, quality 50) for cards and map markers
    func thumbnailImageUrl(for webcam: Webcam) -> String {
        let base = webcam.imageUrl
        let separator = base.contains("?") ? "&" : "?"
        return "\(base)\(separator)thumb=true&quality=50"
    }

    // Get historical image URL for a webcam (supports 0-48 hours ago)
    // Skaping, Viewsurf, and Vision-Env support history
    func historicalImageUrl(for webcam: Webcam, hoursAgo: Double) -> String {
        let hours = min(48, max(0, hoursAgo))

        if hours <= 0 {
            return freshImageUrl(for: webcam)
        }

        // Format hours with period (not comma) for URL compatibility
        // Use Locale.current to avoid locale issues with decimal separator
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        let hoursFormatted = formatter.string(from: NSNumber(value: hours)) ?? String(Int(hours))

        // Append hoursAgo parameter to the proxy URL
        let baseUrl = webcam.imageUrl
        var url = "\(baseUrl)\(baseUrl.contains("?") ? "&" : "?")hoursAgo=\(hoursFormatted)"

        // Add webcam id for Vision-Env (needed for Blob history lookup)
        let source = webcam.source.lowercased()
        if source == "vision-env" {
            url += "&id=\(webcam.id)"
        }

        // Add cache buster to force reload
        url += "&_=\(Int(Date().timeIntervalSince1970))"

        return url
    }

    // Skaping, Viewsurf, and Vision-Env support history via hoursAgo parameter
    // Vision-Env uses Blob storage history captured by cron job
    func supportsHistory(_ webcam: Webcam) -> Bool {
        let source = webcam.source.lowercased()
        return source == "skaping" || source == "viewsurf" || source == "vision-env"
            || source == "windsup" || source == "diabox" || source == "youtube"
    }

    // MARK: - Timeline API

    struct TimelineEntry: Identifiable, Codable, Equatable {
        let timestamp: Int
        let url: String?
        let estimated: Bool?

        var id: Int { timestamp }

        var date: Date {
            Date(timeIntervalSince1970: TimeInterval(timestamp))
        }
    }

    struct TimelineResponse: Codable {
        let source: String
        let count: Int
        let timestamps: [TimelineEntry]
    }

    /// Fetch available timestamps for a webcam's history
    func fetchTimeline(for webcam: Webcam) async -> [TimelineEntry] {
        let source = webcam.source.lowercased()

        guard supportsHistory(webcam) else { return [] }

        // Build query parameters based on source
        var queryParams: [String: String] = ["source": source]

        switch source {
        case "vision-env":
            queryParams["id"] = webcam.id

        case "viewsurf":
            // Extract Viewsurf ID from URL: /api/viewsurf?id=XXX
            if let idMatch = webcam.imageUrl.range(of: "id=([^&]+)", options: .regularExpression) {
                let idValue = String(webcam.imageUrl[idMatch]).replacingOccurrences(of: "id=", with: "")
                queryParams["id"] = idValue
            }
            // Extract slug if present
            if let slugMatch = webcam.imageUrl.range(of: "slug=([^&]+)", options: .regularExpression) {
                let slugValue = String(webcam.imageUrl[slugMatch]).replacingOccurrences(of: "slug=", with: "")
                queryParams["slug"] = slugValue
            }

        case "skaping":
            // Extract path from URL: /api/skaping?path=XXX
            if let pathMatch = webcam.imageUrl.range(of: "path=([^&]+)", options: .regularExpression) {
                let pathValue = String(webcam.imageUrl[pathMatch]).replacingOccurrences(of: "path=", with: "")
                if let decoded = pathValue.removingPercentEncoding {
                    queryParams["path"] = decoded
                } else {
                    queryParams["path"] = pathValue
                }
            }
            // Extract server if present
            if let serverMatch = webcam.imageUrl.range(of: "server=([^&]+)", options: .regularExpression) {
                let serverValue = String(webcam.imageUrl[serverMatch]).replacingOccurrences(of: "server=", with: "")
                queryParams["server"] = serverValue
            }

        case "windsup", "diabox", "youtube":
            queryParams["id"] = webcam.id

        default:
            return []
        }

        // Build URL
        var components = URLComponents(string: "https://api.levent.live/api/webcam-timeline")!
        components.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let url = components.url else { return [] }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue(AppConstants.API.key, forHTTPHeaderField: "X-Api-Key")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return []
            }

            let timelineResponse = try JSONDecoder().decode(TimelineResponse.self, from: data)
            return timelineResponse.timestamps
        } catch {
            Log.error("Failed to fetch webcam timeline: \(error)")
            return []
        }
    }

    /// Get image URL for a specific timestamp
    func imageUrl(for webcam: Webcam, timestamp: Int) -> String {
        let source = webcam.source.lowercased()
        let baseUrl = webcam.imageUrl

        // Add timestamp parameter to proxy URL
        var url = "\(baseUrl)\(baseUrl.contains("?") ? "&" : "?")timestamp=\(timestamp)"

        // Add webcam id for Vision-Env (needed for Blob history lookup)
        if source == "vision-env" && !url.contains("id=") {
            url += "&id=\(webcam.id)"
        }

        return url
    }

    // Fallback to original URL if storage not yet available
    func fallbackImageUrl(for webcam: Webcam) -> String {
        // For Skaping URLs, recalculate timestamp
        let isSkaping = webcam.imageUrl.contains("skaping.com") ||
                        webcam.imageUrl.contains("skaping.s3.gra.io.cloud.ovh.net")

        if isSkaping {
            let components = webcam.imageUrl.components(separatedBy: "/")

            var yearIndex: Int?
            for (index, component) in components.enumerated() {
                if component.count == 4, Int(component) != nil, Int(component)! > 2000 {
                    yearIndex = index
                    break
                }
            }

            if let yearIdx = yearIndex, yearIdx > 0 {
                let baseComponents = components.prefix(yearIdx)
                let baseUrl = baseComponents.joined(separator: "/")

                let now = Date().addingTimeInterval(-60 * 60)
                let formatter = DateFormatter()
                formatter.timeZone = TimeZone(identifier: "UTC")

                formatter.dateFormat = "yyyy"
                let year = formatter.string(from: now)
                formatter.dateFormat = "MM"
                let month = formatter.string(from: now)
                formatter.dateFormat = "dd"
                let day = formatter.string(from: now)
                formatter.dateFormat = "HH"
                let hour = formatter.string(from: now)

                let calendar = Calendar.current
                let minute = calendar.component(.minute, from: now)
                let minuteStr = minute < 30 ? "00" : "30"

                return "\(baseUrl)/\(year)/\(month)/\(day)/\(hour)-\(minuteStr).jpg"
            }
        }

        return webcam.imageUrl
    }

    // MARK: - Viewsurf Live Stream Mapping
    // Stream URLs discovered from Viewsurf via Quanteec CDN
    // To find more streams: inspect pv.viewsurf.com pages for "type": "live" entries
    // Only "live" type streams work (not "video" or "pano" types)
    private static let viewsurfStreamUrls: [String: String] = [
        // Bretagne - Finistère
        "vs-benodet": "https://ds2-cache.quanteec.com/contents/encodings/live/56caa721-02b2-4031-3430-3130-6d61-63-b9f9-f23307135ec5d/media_0.m3u8",
        "vs-penmarch": "https://ds2-cache.quanteec.com/contents/encodings/live/068f1c25-1be9-4494-3439-3330-6d61-63-837f-3e21424f20a2d/media_0.m3u8", // Port de Kérity
        "vs-penmarch-st-guenole": "https://ds2-cache.quanteec.com/contents/encodings/live/42de5499-f4e1-425f-3236-3130-6d61-63-8320-013bf9662d2cd/media_0.m3u8",
        "vs-guilvinec": "https://ds2-cache.quanteec.com/contents/encodings/live/7b24320f-47ce-4242-3333-3230-6d61-63-9244-9275136a96bdd/media_0.m3u8",
        "vs-cap-coz": "https://ds2-cache.quanteec.com/contents/encodings/live/5a3840a9-818c-432d-3831-3230-6d61-63-b94e-ec74c6293339d/media_0.m3u8",
        "vs-crozon": "https://ds2-cache.quanteec.com/contents/encodings/live/a57d6076-bcdd-4e1b-3738-3130-6d61-63-ba69-112b409efb73d/media_0.m3u8",
        "vs-mousterlin": "https://ds2-cache.quanteec.com/contents/encodings/live/357fc1ec-7bbe-404f-3631-3230-6d61-63-a54d-53c79aaee76ed/media_0.m3u8",
        "vs-pont-labbe": "https://ds2-cache.quanteec.com/contents/encodings/live/927939d7-996a-4e66-3530-3430-6d61-63-b236-56683e39d5e9d/media_0.m3u8",
        "vs-paimpol": "https://ds2-cache.quanteec.com/contents/encodings/live/8ca4ab2a-c52d-4198-3238-3330-6d61-63-ac39-531978ff7942d/media_0.m3u8",
        "vs-combrit": "https://ds2-cache.quanteec.com/contents/encodings/live/2fe87ffd-1ac2-4f9c-3138-3130-6d61-63-9b25-a02ee9338d50d/media_0.m3u8",
        "vs-glenan": "https://ds1-cache.quanteec.com/contents/encodings/live/f96e5f26-57d2-42ab-3239-3530-6d61-63-a7d3-96dd6b2ec090d/media_0.m3u8", // Île Saint-Nicolas

        // Bretagne - Morbihan / Loire-Atlantique
        "vs-croisic": "https://ds2-cache.quanteec.com/contents/encodings/live/6bac6633-41ad-4dd8-3432-3330-6d61-63-afab-bfcab638ff8fd/media_0.m3u8",
        "vs-ile-tudy": "https://ds2-cache.quanteec.com/contents/encodings/live/6bac6633-41ad-4dd8-3432-3330-6d61-63-afab-bfcab638ff8fd/media_0.m3u8",
        "vs-pouliguen": "https://ds2-cache.quanteec.com/contents/encodings/live/94798048-1561-4a0a-3832-3330-6d61-63-8476-0a7d558c33d3d/media_0.m3u8",

        // Vendée / Charentes

        // Gironde / Landes
        "vs-lacanau": "https://ds2-cache.quanteec.com/contents/encodings/live/67eb6464-055f-47cb-3730-3330-6d61-63-abc5-fa5259757cc4d/media_0.m3u8",
        "vs-arcachon": "https://ds2-cache.quanteec.com/contents/encodings/live/001f0c90-60c6-4121-3134-3030-6d61-63-a2eb-acfa247e6c29d/media_0.m3u8", // Jetée Thiers
        "vs-seignosse": "https://ds2-cache.quanteec.com/contents/encodings/live/8da4aff9-9afb-47ce-3937-3430-6d61-63-b10b-bae5e6dead40d/media_0.m3u8",


        // Normandie
        "vs-le-havre": "https://ds2-cache.quanteec.com/contents/encodings/live/c6ac4174-ee79-4e08-3632-3330-6d61-63-9efb-ce2d3fb197b0d/media_0.m3u8",
        "vs-dieppe": "https://ds2-cache.quanteec.com/contents/encodings/live/41b8fbe2-cf49-4396-3139-3130-6d61-63-b29f-ad20fe94d576d/media_0.m3u8", // Sémaphore
        "vs-dieppe-2": "https://ds2-cache.quanteec.com/contents/encodings/live/90182dbb-0d89-45e1-3531-3730-6d61-63-8bf8-edad6928536ed/media_0.m3u8", // Marcel Paul
        "vs-siouville": "https://ds2-cache.quanteec.com/contents/encodings/live/a89f3474-9d1c-40dd-3437-3230-6d61-63-a5fd-58da85d36f6cd/media_0.m3u8",
        "vs-goury": "https://ds2-cache.quanteec.com/contents/encodings/live/ae1a4a8c-784b-4571-3537-3230-6d61-63-a65b-ceb2396bd8add/media_0.m3u8", // La Hague
        "vs-barneville": "https://ds2-cache.quanteec.com/contents/encodings/live/273a3e7a-b125-4cb1-3839-3030-6d61-63-a49f-22af76e7fbf2d/media_0.m3u8",

        // Hauts-de-France
        "vs-dunkerque": "https://ds2-cache.quanteec.com/contents/encodings/live/8d9f7a17-a395-4be6-3739-3130-6d61-63-b32b-4069d95be7a5d/media_0.m3u8", // Dunes de Flandres
        "vs-bray-dunes": "https://ds2-cache.quanteec.com/contents/encodings/live/4e0100d6-7bc4-43be-3839-3130-6d61-63-bd66-bcfd64e27574d/media_0.m3u8",
        "vs-zuydcoote": "https://ds2-cache.quanteec.com/contents/encodings/live/8f0170c0-1b41-48f9-3030-3230-6d61-63-98e4-bc495cd8d793d/media_0.m3u8",
        "vs-calais": "https://ds2-cache.quanteec.com/contents/encodings/live/d5e9f551-7435-4ea6-3532-3130-6d61-63-916e-ff1d72543cced/media_0.m3u8",
        "vs-hardelot": "https://ds2-cache.quanteec.com/contents/encodings/live/16d1ad82-49dc-491a-3433-3230-6d61-63-a59d-fc77596c2e6dd/media_0.m3u8",

        // Pays Basque
        "vs-anglet": "https://ds2-cache.quanteec.com/contents/encodings/live/c56ac32d-4df6-4924-3430-3030-6d61-63-9e97-d84cc86e129bd/media_0.m3u8", // Plage de l'Océan

        // Côte d'Azur
        "vs-nice": "https://ds2-cache.quanteec.com/contents/encodings/live/44325ee8-0cde-4f0c-3737-3330-6d61-63-a448-371421fe696ad/media_0.m3u8", // Aston La Scala
        "vs-frejus": "https://ds2-cache.quanteec.com/contents/encodings/live/cc8b8ffe-1f03-4d8b-3538-3530-6d61-63-ada0-ea8fb07459bfd/media_0.m3u8",

        // Occitanie
        "vs-marseillan": "https://ds2-cache.quanteec.com/contents/encodings/live/7fcccb75-27f4-404a-3135-3330-6d61-63-87f3-3b4524b27fd3d/media_0.m3u8",
        "vs-balaruc": "https://ds2-cache.quanteec.com/contents/encodings/live/96788152-a05c-4ec4-3339-3030-6d61-63-9805-c3e488218fddd/media_0.m3u8",

        // ═══════════════════════════════════════════════════════════════
        // Vision-Environnement Live Streams (visionenvironnement.quanteec.com)
        // ═══════════════════════════════════════════════════════════════

        // Bretagne - Finistère
        "ve-pointe-raz": "https://visionenvironnement.quanteec.com/contents/encodings/live/0c6e6ed3-7436-48c8-746c-7561-6665-64-9230-1f27453a1a3bd/media_0.m3u8",
        "ve-ile-sein": "https://visionenvironnement.quanteec.com/contents/encodings/live/3665df87-975d-4e72-746c-7561-6665-64-9547-dc2c348448c1d/media_0.m3u8",
        "ve-brest-port": "https://visionenvironnement.quanteec.com/contents/encodings/live/6fbd1472-686d-4b5d-746c-7561-6665-64-a655-aa01b333c1d6d/media_0.m3u8",
        "ve-audierne-port": "https://visionenvironnement.quanteec.com/contents/encodings/live/917376b5-2fd1-4282-746c-7561-6665-64-b293-6479a76ee9cad/media_0.m3u8",
        "ve-douarnenez-port": "https://visionenvironnement.quanteec.com/contents/encodings/live/1f1a5b37-b247-4e15-746c-7561-6665-64-aa5e-d27be2eaf3d7d/media_0.m3u8",
        "ve-carantec": "https://visionenvironnement.quanteec.com/contents/encodings/live/7cf698e3-1333-4ac2-746c-7561-6665-64-aa71-3e3b0dc2044bd/media_0.m3u8",
        "ve-locquirec": "https://visionenvironnement.quanteec.com/contents/encodings/live/f805f657-0d7f-4d9e-746c-7561-6665-64-a08c-2306bf8dfd65d/media_0.m3u8",
        "ve-plougonvelin": "https://visionenvironnement.quanteec.com/contents/encodings/live/2d3150ea-fd0f-4d15-746c-7561-6665-64-9d2b-705100911459d/media_0.m3u8",
        "ve-portsall": "https://visionenvironnement.quanteec.com/contents/encodings/live/25eb1639-dd59-4861-746c-7561-6665-64-97e3-3118969944e0d/media_0.m3u8",
        "ve-plouescat": "https://visionenvironnement.quanteec.com/contents/encodings/live/4b73b419-ea63-42aa-746c-7561-6665-64-989d-ab5cfb1e8047d/media_0.m3u8",
        "ve-lannion": "https://visionenvironnement.quanteec.com/contents/encodings/live/aea45e74-e4e7-43e7-746c-7561-6665-64-baa2-92cacfe203dad/media_0.m3u8",

        // Bretagne - Côtes-d'Armor
        "ve-erquy": "https://visionenvironnement.quanteec.com/contents/encodings/live/32a8bd52-3fbf-4583-746c-7561-6665-64-9ad5-7187f0d804d0d/media_0.m3u8",
        "ve-binic": "https://visionenvironnement.quanteec.com/contents/encodings/live/eaf789b3-a03f-4137-746c-7561-6665-64-9685-3288bd76a811d/media_0.m3u8",

        // Bretagne - Morbihan
        "ve-gavres": "https://visionenvironnement.quanteec.com/contents/encodings/live/3d1106a9-4c03-45b6-746c-7561-6665-64-90db-5c15b5f9deb2d/media_0.m3u8",
        "ve-penestin": "https://visionenvironnement.quanteec.com/contents/encodings/live/6c8db124-f44e-4da1-746c-7561-6665-64-a7db-77db9ffc8c43d/media_0.m3u8",

        // Normandie
        "ve-etretat": "https://visionenvironnement.quanteec.com/contents/encodings/live/2fe83b0a-8f3f-4531-746c-7561-6665-64-b260-5af4b6d5cef8d/media_0.m3u8",
        "ve-fecamp": "https://visionenvironnement.quanteec.com/contents/encodings/live/c012202e-8b84-4d34-746c-7561-6665-64-988c-aeb3d9370d67d/media_0.m3u8",
        "ve-le-havre": "https://visionenvironnement.quanteec.com/contents/encodings/live/263a0cac-1bba-43e5-746c-7561-6665-64-8139-bc64fa1d053cd/media_0.m3u8",
        "ve-cabourg": "https://visionenvironnement.quanteec.com/contents/encodings/live/d4a136d1-bf09-4fd0-746c-7561-6665-64-9822-9b9fcebbda22d/media_0.m3u8",
        "ve-ouistreham": "https://visionenvironnement.quanteec.com/contents/encodings/live/5b4eeade-a6e3-40ae-746c-7561-6665-64-bee6-1fcec990850fd/media_0.m3u8",
        "ve-jullouville": "https://visionenvironnement.quanteec.com/contents/encodings/live/0868201a-60b5-443a-746c-7561-6665-64-9924-5781cdbe241dd/media_0.m3u8",
        "ve-houlgate": "https://visionenvironnement.quanteec.com/contents/encodings/live/d73a3466-b3fa-41e1-746c-7561-6665-64-8d74-2d5c40dc47a5d/media_0.m3u8",
        "ve-langrune": "https://visionenvironnement.quanteec.com/contents/encodings/live/81f14c06-ae24-449d-746c-7561-6665-64-bcfb-e2e69ada63d8d/media_0.m3u8",
        "ve-luc-sur-mer": "https://visionenvironnement.quanteec.com/contents/encodings/live/fbf626d6-c8ec-4bef-746c-7561-6665-64-a94b-383556d07799d/media_0.m3u8",
        "ve-st-aubin": "https://visionenvironnement.quanteec.com/contents/encodings/live/3a30f42b-13ee-4a64-746c-7561-6665-64-9a27-19c769ef3672d/media_0.m3u8",
        "ve-pirou": "https://visionenvironnement.quanteec.com/contents/encodings/live/c60ca2ff-b566-470a-746c-7561-6665-64-81b7-43ffed9b2eb5d/media_0.m3u8",
        "ve-st-germain": "https://visionenvironnement.quanteec.com/contents/encodings/live/7ff7e221-bd4a-4aca-746c-7561-6665-64-b645-665249ac2217d/media_0.m3u8",

        // Vendée / Charentes
        "ve-noirmoutier": "https://visionenvironnement.quanteec.com/contents/encodings/live/20a0e6d4-aeef-436b-746c-7561-6665-64-aa29-b5b878736016d/media_0.m3u8",
        "ve-gois": "https://visionenvironnement.quanteec.com/contents/encodings/live/b5e7710b-94c9-48a0-746c-7561-6665-64-aeac-6a516e868621d/media_0.m3u8",
        "ve-herbaudiere": "https://visionenvironnement.quanteec.com/contents/encodings/live/c2262b2a-ed62-416b-746c-7561-6665-64-8740-7af835c1d5d5d/media_0.m3u8",
        "ve-bourcefranc": "https://visionenvironnement.quanteec.com/contents/encodings/live/e1b556f8-5a51-4fe9-746c-7561-6665-64-bd92-03e8da54d339d/media_0.m3u8",
        "ve-oleron-cotiniere": "https://visionenvironnement.quanteec.com/contents/encodings/live/4901e686-1e49-4782-746c-7561-6665-64-8d84-b748a07c35cad/media_0.m3u8",
        "ve-oleron-perroche": "https://visionenvironnement.quanteec.com/contents/encodings/live/f7a7c631-e4b9-42e5-746c-7561-6665-64-9bdc-cc1bf762df87d/media_0.m3u8",
        "ve-st-trojan": "https://visionenvironnement.quanteec.com/contents/encodings/live/dc8e9da3-c2c1-4267-746c-7561-6665-64-9eca-e29660a3557fd/media_0.m3u8",

        // Corse
        "ve-cargese": "https://visionenvironnement.quanteec.com/contents/encodings/live/41e2c7ad-2e0f-42f6-746c-7561-6665-64-8465-8bb7389e4290d/media_0.m3u8",
        "ve-ajaccio-pano": "https://visionenvironnement.quanteec.com/contents/encodings/live/e735eda0-07e8-4d5f-746c-7561-6665-64-8934-60bc461532e7d/media_0.m3u8",

        // Méditerranée
        "ve-carro": "https://visionenvironnement.quanteec.com/contents/encodings/live/28060ac0-e250-412d-746c-7561-6665-64-9158-465d2fa63bb6d/media_0.m3u8",
    ]

    /// Get live stream URL for a webcam (if available)
    func liveStreamUrl(for webcam: Webcam) -> String? {
        // First check if webcam already has a stream URL
        if let streamUrl = webcam.streamUrl, !streamUrl.isEmpty {
            return streamUrl
        }

        // Check our known Viewsurf streams mapping
        if let streamUrl = Self.viewsurfStreamUrls[webcam.id] {
            return streamUrl
        }

        return nil
    }

    /// Check if a webcam has a live stream available
    func hasLiveStream(_ webcam: Webcam) -> Bool {
        liveStreamUrl(for: webcam) != nil
    }

    /// Check if the stream is a YouTube URL (needs WKWebView, not AVPlayer)
    func isYouTubeStream(_ webcam: Webcam) -> Bool {
        guard let url = liveStreamUrl(for: webcam) else { return false }
        return url.contains("youtube.com") || url.contains("youtu.be")
    }

    /// Extract YouTube embed URL from any YouTube URL format
    func youTubeEmbedUrl(for webcam: Webcam) -> String? {
        guard let url = liveStreamUrl(for: webcam) else { return nil }
        let videoId: String?

        if url.contains("/embed/") {
            videoId = url.components(separatedBy: "/embed/").last?.components(separatedBy: "?").first
        } else if url.contains("youtu.be/") {
            videoId = url.components(separatedBy: "youtu.be/").last?.components(separatedBy: "?").first
        } else if url.contains("/live/") {
            videoId = url.components(separatedBy: "/live/").last?.components(separatedBy: "?").first
        } else if let components = URLComponents(string: url) {
            videoId = components.queryItems?.first(where: { $0.name == "v" })?.value
        } else {
            videoId = nil
        }

        guard let vid = videoId, !vid.isEmpty else { return nil }
        return "https://www.youtube.com/embed/\(vid)?autoplay=1&mute=1&playsinline=1"
    }

    // Fallback static webcams (used if API fails)
    private static let fallbackWebcams: [Webcam] = [
        // Placeholder entry while loading
        Webcam(
            id: "placeholder",
            name: "Chargement...",
            location: "France",
            region: nil,
            latitude: 46.5,
            longitude: 2.5,
            imageUrl: "",
            streamUrl: nil,
            source: "Skaping",
            refreshInterval: 600
        )
    ]
}
