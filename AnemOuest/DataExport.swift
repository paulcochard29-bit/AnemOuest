import Foundation
import UIKit
import SwiftUI

// MARK: - Data Export Service
/// Export wind observations, forecasts, and favorites to various formats.

enum DataExport {

    // MARK: - CSV Export

    /// Export wind observations to CSV string
    static func windObservationsToCSV(
        stationName: String,
        samples: [WCChartSample]
    ) -> String {
        var csv = "Station,Date,Heure,Type,Valeur (noeuds)\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        for sample in samples.sorted(by: { $0.t < $1.t }) {
            let date = dateFormatter.string(from: sample.t)
            let time = timeFormatter.string(from: sample.t)
            let type: String
            switch sample.kind {
            case .wind: type = "Vent moyen"
            case .gust: type = "Rafale"
            case .dir: type = "Direction"
            }
            csv += "\(stationName),\(date),\(time),\(type),\(String(format: "%.1f", sample.value))\n"
        }

        return csv
    }

    /// Export forecast to CSV
    static func forecastToCSV(forecast: ForecastData) -> String {
        var csv = "Modele,Date,Heure,Vent (km/h),Vent (nds),Rafale (km/h),Rafale (nds),Direction,Temperature,Precipitations,Couverture nuageuse,Humidite,Pression\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        for h in forecast.hourly {
            let date = dateFormatter.string(from: h.time)
            let time = timeFormatter.string(from: h.time)
            csv += "\(forecast.model.displayName),\(date),\(time),"
            csv += "\(String(format: "%.1f", h.windSpeed)),\(String(format: "%.1f", h.windSpeedKnots)),"
            csv += "\(String(format: "%.1f", h.windGusts)),\(String(format: "%.1f", h.gustsKnots)),"
            csv += "\(String(format: "%.0f", h.windDirection)),\(String(format: "%.1f", h.temperature)),"
            csv += "\(String(format: "%.1f", h.precipitation)),\(h.cloudCover),"
            csv += "\(h.humidity),\(String(format: "%.1f", h.pressureMSL ?? 0))\n"
        }

        return csv
    }

    /// Export favorites list to CSV
    static func favoritesToCSV(favorites: [FavoriteStation]) -> String {
        var csv = "Nom,Source,Latitude,Longitude,Alerte vent (nds),Date ajout\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        for fav in favorites {
            csv += "\(fav.name),\(fav.source),"
            csv += "\(String(format: "%.6f", fav.latitude)),\(String(format: "%.6f", fav.longitude)),"
            csv += "\(fav.windAlertThreshold ?? 0),"
            csv += "\(dateFormatter.string(from: fav.addedAt))\n"
        }

        return csv
    }

    // MARK: - Share Helpers

    /// Create a temporary CSV file and return its URL for sharing
    static func createCSVFile(content: String, filename: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(filename).csv")

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            Log.error("Failed to write CSV: \(error)")
            return nil
        }
    }

    /// Share a file via UIActivityViewController
    @MainActor
    static func share(items: [Any]) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first,
              let rootVC = window.rootViewController else { return }

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)

        // iPad needs popover anchor
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        rootVC.present(activityVC, animated: true)
    }

    /// Export wind data and present share sheet
    @MainActor
    static func shareWindData(stationName: String, samples: [WCChartSample]) {
        let csv = windObservationsToCSV(stationName: stationName, samples: samples)
        let safeName = stationName.replacingOccurrences(of: " ", with: "_")
        guard let url = createCSVFile(content: csv, filename: "vent_\(safeName)") else { return }
        share(items: [url])
    }

    /// Export forecast and present share sheet
    @MainActor
    static func shareForecast(forecast: ForecastData, locationName: String) {
        let csv = forecastToCSV(forecast: forecast)
        let safeName = locationName.replacingOccurrences(of: " ", with: "_")
        guard let url = createCSVFile(content: csv, filename: "prevision_\(safeName)_\(forecast.model.rawValue)") else { return }
        share(items: [url])
    }

    /// Export favorites and present share sheet
    @MainActor
    static func shareFavorites(favorites: [FavoriteStation]) {
        let csv = favoritesToCSV(favorites: favorites)
        guard let url = createCSVFile(content: csv, filename: "favoris_anemouest") else { return }
        share(items: [url])
    }
}

