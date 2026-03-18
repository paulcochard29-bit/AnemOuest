//
//  SpotAirService.swift
//  AnemOuest
//
//  Service for SpotAir API (paragliding spots + webcams)
//

import Foundation
import CoreLocation

// MARK: - SpotAir Service

actor SpotAirService {
    static let shared = SpotAirService()

    private let spotsURL = "https://api.levent.live/api/paragliding-spots"
    private let webcamsURL = "https://data.spotair.mobi/webcams/webcams-get.php"
    private let webcamsApiKey = "n5xT2BZ42FtM8kNXlkQ8tA=="

    // Cache
    private var cachedSpots: [ParaglidingSpot] = []
    private var spotsLoaded = false
    private var cachedWebcams: [SpotAirWebcam] = []
    private var lastWebcamsBounds: (south: Double, north: Double, west: Double, east: Double)?

    private init() {}

    // MARK: - Fetch Spots (from our API - all France spots pre-cached)

    func fetchSpots(south: Double, north: Double, west: Double, east: Double) async throws -> [ParaglidingSpot] {
        // All spots are loaded once and filtered client-side by bounding box
        if !spotsLoaded {
            guard let url = URL(string: spotsURL) else { throw URLError(.badURL) }

            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue(AppConstants.API.key, forHTTPHeaderField: "X-Api-Key")

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                Log.network("Paragliding spots API: HTTP \(httpResponse.statusCode)")
                throw URLError(.badServerResponse)
            }

            let apiResponse = try JSONDecoder().decode(CachedSpotsResponse.self, from: data)

            cachedSpots = apiResponse.spots.map { dto in
                ParaglidingSpot(
                    id: dto.id,
                    name: dto.name,
                    latitude: dto.latitude,
                    longitude: dto.longitude,
                    altitude: dto.altitude,
                    orientations: dto.orientations,
                    orientationsDefavo: dto.orientationsDefavo,
                    type: ParaglidingSpotType.fromString(dto.type),
                    level: dto.level.flatMap { ParaglidingLevel(rawValue: $0) },
                    spotDescription: dto.description,
                    city: dto.city,
                    isValid: true
                )
            }

            spotsLoaded = true
            Log.network("Paragliding: loaded \(cachedSpots.count) spots from API")
        }

        // Filter by visible bounding box
        let margin = 0.2
        return cachedSpots.filter { spot in
            spot.latitude >= (south - margin) && spot.latitude <= (north + margin) &&
            spot.longitude >= (west - margin) && spot.longitude <= (east + margin)
        }
    }

    // MARK: - Fetch Webcams

    func fetchWebcams(south: Double, north: Double, west: Double, east: Double) async throws -> [SpotAirWebcam] {
        // Return cache if same bounds
        if let last = lastWebcamsBounds,
           south >= last.south - 0.1 && north <= last.north + 0.1 &&
           west >= last.west - 0.1 && east <= last.east + 0.1 {
            return cachedWebcams
        }

        let margin = 0.2
        let s = south - margin
        let n = north + margin
        let w = west - margin
        let e = east + margin

        guard let url = URL(string: webcamsURL) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(webcamsApiKey, forHTTPHeaderField: "X-Spotair-Apikey")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "sortie=json&coordonnees=\(s),\(n),\(w),\(e)".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            Log.network("SpotAir webcams: HTTP \(httpResponse.statusCode)")
            throw URLError(.badServerResponse)
        }

        let apiResponse = try JSONDecoder().decode(SpotAirWebcamsResponse.self, from: data)

        guard apiResponse.code == 0, let webcamsData = apiResponse.data else {
            Log.error("SpotAir webcams error: \(apiResponse.msg ?? "unknown")")
            throw URLError(.cannotParseResponse)
        }

        let webcams = webcamsData.compactMap { dto -> SpotAirWebcam? in
            guard dto.etat == "V" else { return nil }
            guard let urlImage = dto.url_image, !urlImage.isEmpty else { return nil }
            guard dto.latitude != 0 && dto.longitude != 0 else { return nil }

            return SpotAirWebcam(
                id: "spotair_cam_\(dto.id)",
                name: dto.nom ?? "Webcam \(dto.id)",
                latitude: dto.latitude,
                longitude: dto.longitude,
                altitude: dto.altitude ?? 0,
                imageUrl: urlImage,
                direction: dto.direction,
                fieldOfView: dto.champ,
                isOnline: dto.statut_enligne == "E",
                sourceUrl: dto.url_page
            )
        }

        Log.network("SpotAir: loaded \(webcams.count) webcams")

        cachedWebcams = webcams
        lastWebcamsBounds = (s, n, w, e)

        return webcams
    }

    // MARK: - Orientation Bitmask Decoder

    /// Decodes SpotAir orientation bitmask to direction strings
    /// bit0=N, bit1=NE, bit2=E, bit3=SE, bit4=S, bit5=SW, bit6=W, bit7=NW
    static func decodeOrientationBitmask(_ bitmask: Int) -> [String] {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        var result: [String] = []
        for i in 0..<8 {
            if (1 << i) & bitmask != 0 {
                result.append(directions[i])
            }
        }
        return result
    }
}

// MARK: - SpotAir Webcam Model

struct SpotAirWebcam: Identifiable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let altitude: Int
    let imageUrl: String
    let direction: Int?
    let fieldOfView: Int?
    let isOnline: Bool
    let sourceUrl: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Extract provider name from source URL domain
    var sourceName: String? {
        guard let sourceUrl, let url = URL(string: sourceUrl),
              let host = url.host?.lowercased() else { return nil }
        if host.contains("skaping") { return "Skaping" }
        if host.contains("trinum") { return "Trinum" }
        if host.contains("viewsurf") { return "ViewSurf" }
        if host.contains("webcam") { return host.replacingOccurrences(of: "www.", with: "") }
        // Fallback: use domain without www
        let clean = host.replacingOccurrences(of: "www.", with: "")
        let parts = clean.split(separator: ".")
        if parts.count >= 2 {
            return String(parts[0]).capitalized
        }
        return clean.capitalized
    }
}

// MARK: - Cached Spots API Response Models

private struct CachedSpotsResponse: Codable {
    let spots: [CachedSpotDTO]
    let count: Int
    let timestamp: String
}

private struct CachedSpotDTO: Codable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let altitude: Int
    let orientations: [String]
    let orientationsDefavo: [String]
    let type: String
    let level: Int?
    let description: String?
    let city: String?
}

// MARK: - Webcam API Response Models

private struct SpotAirWebcamsResponse: Codable {
    let code: Int
    let msg: String?
    let data: [SpotAirWebcamDTO]?
}

private struct SpotAirWebcamDTO: Codable {
    let id: Int
    let etat: String?
    let nom: String?
    let pays: String?
    let latitude: Double
    let longitude: Double
    let altitude: Int?
    let direction: Int?
    let champ: Int?
    let url_image: String?
    let periodicite: Int?
    let largeur: Int?
    let hauteur: Int?
    let url_page: String?
    let description: String?
    let statut_enligne: String?
}
