//
//  HolfuyHistoryService.swift
//  AnemOuest
//
//  Service for fetching Holfuy data directly from holfuy.com
//

import Foundation

actor HolfuyHistoryService {
    static let shared = HolfuyHistoryService()

    private init() {}

    // MARK: - Fetch Latest Data (Real-time)

    /// Fetch current/latest wind data for a Holfuy station
    /// Returns the most recent observation from the history data
    func fetchLatestData(stationId: String) async -> HolfuyObservation? {
        let numericId = stationId.replacingOccurrences(of: "holfuy_", with: "")

        guard let url = URL(string: "https://holfuy.com/dynamic/graphs/tdarr\(numericId).js") else {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let jsContent = String(data: data, encoding: .utf8) else {
                return nil
            }

            let timestamps = parseJSArray(jsContent, variableName: "unt")
            let speeds = parseJSNumberArray(jsContent, variableName: "gd_speed")
            let gusts = parseJSNumberArray(jsContent, variableName: "gd_gust")
            let directions = parseJSNumberArray(jsContent, variableName: "gd_direction")
            let temps = parseJSDoubleArray(jsContent, variableName: "gd_temp")

            guard !timestamps.isEmpty else { return nil }

            // Get last (most recent) values
            let lastIndex = timestamps.count - 1

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
            dateFormatter.timeZone = TimeZone(identifier: "Europe/Paris")

            guard let date = dateFormatter.date(from: timestamps[lastIndex]) else { return nil }

            let speed = lastIndex < speeds.count ? speeds[lastIndex] : 0
            let gust = lastIndex < gusts.count ? gusts[lastIndex] : 0
            let direction = lastIndex < directions.count ? directions[lastIndex] : 0
            let temp: Double? = lastIndex < temps.count ? temps[lastIndex] : nil

            // Convert km/h to knots
            return HolfuyObservation(
                timestamp: date,
                windSpeed: Double(speed) * 0.539957,
                gustSpeed: Double(gust) * 0.539957,
                direction: Double(direction),
                temperature: temp
            )
        } catch {
            Log.network("Holfuy: Error fetching latest data for \(numericId): \(error)")
            return nil
        }
    }

    /// Fetch latest data for multiple stations in parallel
    func fetchLatestDataBatch(stationIds: [String]) async -> [String: HolfuyObservation] {
        var results: [String: HolfuyObservation] = [:]

        await withTaskGroup(of: (String, HolfuyObservation?).self) { group in
            for stationId in stationIds {
                group.addTask {
                    let obs = await self.fetchLatestData(stationId: stationId)
                    return (stationId, obs)
                }
            }

            for await (stationId, obs) in group {
                if let obs = obs {
                    results[stationId] = obs
                }
            }
        }

        return results
    }

    // MARK: - Fetch History

    /// Fetch historical data for a Holfuy station
    /// - Parameters:
    ///   - stationId: The Holfuy station ID (e.g., "1146" or "holfuy_1146")
    ///   - hours: Number of hours of history to return (filters from ~5 days available)
    /// - Returns: Array of observations sorted by time
    func fetchHistory(stationId: String, hours: Int = 24) async throws -> [HolfuyObservation] {
        // Extract numeric ID from stableId format (holfuy_1146 -> 1146)
        let numericId = stationId.replacingOccurrences(of: "holfuy_", with: "")

        guard let url = URL(string: "https://holfuy.com/dynamic/graphs/tdarr\(numericId).js") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            Log.network("Holfuy History: HTTP \(httpResponse.statusCode) for station \(numericId)")
            throw URLError(.badServerResponse)
        }

        guard let jsContent = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        // Parse the JavaScript arrays
        let timestamps = parseJSArray(jsContent, variableName: "unt")
        let speeds = parseJSNumberArray(jsContent, variableName: "gd_speed")
        let gusts = parseJSNumberArray(jsContent, variableName: "gd_gust")
        let directions = parseJSNumberArray(jsContent, variableName: "gd_direction")
        let temps = parseJSDoubleArray(jsContent, variableName: "gd_temp")

        guard !timestamps.isEmpty else {
            Log.warning("Holfuy History: No timestamps found for station \(numericId)")
            return []
        }

        // Build observations
        var observations: [HolfuyObservation] = []
        let cutoffDate = Date().addingTimeInterval(-Double(hours) * 3600)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        dateFormatter.timeZone = TimeZone(identifier: "Europe/Paris") // Holfuy uses CET/CEST

        for i in 0..<timestamps.count {
            guard let date = dateFormatter.date(from: timestamps[i]) else { continue }

            // Filter by hours
            if date < cutoffDate { continue }

            let speed = i < speeds.count ? speeds[i] : 0
            let gust = i < gusts.count ? gusts[i] : 0
            let direction = i < directions.count ? directions[i] : 0
            let temp: Double? = i < temps.count ? temps[i] : nil

            // Convert km/h to knots (1 km/h = 0.539957 knots)
            let windKnots = Double(speed) * 0.539957
            let gustKnots = Double(gust) * 0.539957

            observations.append(HolfuyObservation(
                timestamp: date,
                windSpeed: windKnots,
                gustSpeed: gustKnots,
                direction: Double(direction),
                temperature: temp
            ))
        }

        Log.network("Holfuy History: Got \(observations.count) observations for \(numericId) (last \(hours)h)")

        return observations.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - JavaScript Parsing

    private func parseJSArray(_ js: String, variableName: String) -> [String] {
        // Find: var variableName = ['value1','value2',...]
        guard let startRange = js.range(of: "var \(variableName) = [") else { return [] }

        let afterStart = js[startRange.upperBound...]
        guard let endRange = afterStart.range(of: "];") else { return [] }

        let arrayContent = String(afterStart[..<endRange.lowerBound])

        // Parse string values (removing quotes)
        var values: [String] = []
        var current = ""
        var inString = false

        for char in arrayContent {
            if char == "'" {
                if inString {
                    values.append(current)
                    current = ""
                }
                inString = !inString
            } else if inString {
                current.append(char)
            }
        }

        return values
    }

    private func parseJSNumberArray(_ js: String, variableName: String) -> [Int] {
        // Find: var variableName = [1,2,3,...]
        guard let startRange = js.range(of: "var \(variableName) = [") else { return [] }

        let afterStart = js[startRange.upperBound...]
        guard let endRange = afterStart.range(of: "];") else { return [] }

        let arrayContent = String(afterStart[..<endRange.lowerBound])

        // Parse numbers
        return arrayContent
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    private func parseJSDoubleArray(_ js: String, variableName: String) -> [Double] {
        guard let startRange = js.range(of: "var \(variableName) = [") else { return [] }

        let afterStart = js[startRange.upperBound...]
        guard let endRange = afterStart.range(of: "];") else { return [] }

        let arrayContent = String(afterStart[..<endRange.lowerBound])

        return arrayContent
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }
}

// MARK: - Model

struct HolfuyObservation {
    let timestamp: Date
    let windSpeed: Double   // knots
    let gustSpeed: Double   // knots
    let direction: Double   // degrees
    let temperature: Double? // °C
}
