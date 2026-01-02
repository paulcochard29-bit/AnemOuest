import Foundation

final class WindService {

    enum WindServiceError: Error {
        case badURL
        case badHTTP(Int)
        case empty
    }

    /// timeFrameMinutes = param `time_frame` du backend (ex: 60 / 36 / 144)
    func fetchSeries(sensorId: String, timeFrameMinutes: Int) async throws -> [WCWindObservation] {
        guard let url = URL(string: "https://backend.windmorbihan.com/observations/chart.json?sensor=\(sensorId)&time_frame=\(timeFrameMinutes)") else {
            throw WindServiceError.badURL
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("AnemOuest/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw WindServiceError.badHTTP(http.statusCode)
        }

        // 1) Format principal : array de WCWindObservation
        if let decoded = try? JSONDecoder().decode([WCWindObservation].self, from: data) {
            let merged = mergeAndFilter(decoded)
            if merged.isEmpty { throw WindServiceError.empty }
            return merged
        }

        // 2) Fallback : payload type Highcharts
        let json = try JSONSerialization.jsonObject(with: data)
        let seriesArr = findSeries(in: json)

        var windByTs: [Int64: Double] = [:]
        var gustByTs: [Int64: Double] = [:]
        var dirByTs:  [Int64: Double] = [:]
        var anySeries: [(name: String, points: [Int64: Double])] = []

        for s in seriesArr {
            let rawName = ((s["name"] as? String) ?? (s["id"] as? String) ?? (s["key"] as? String) ?? "")
            let name = rawName.lowercased()

            let detected: SeriesKindOrDir?
            if name.contains("raf") || name.contains("gust") || name.contains("max") {
                detected = .gust
            } else if name.contains("dir") || name.contains("direction") || name.contains("angle") || name.contains("deg") {
                detected = .dir
            } else if name.contains("vent") || name.contains("wind") || name.contains("vitesse") || name.contains("speed") || name.contains("moy") || name.contains("mean") {
                detected = .wind
            } else {
                detected = nil
            }

            let pointsAny = extractPoints(from: s)
            if pointsAny.isEmpty { continue }

            var local: [Int64: Double] = [:]
            for p in pointsAny {
                let (tsMaybe, valMaybe) = parsePoint(p)
                guard let tsRaw = tsMaybe, let v = valMaybe else { continue }

                let tsMs: Int64
                if tsRaw > 2_000_000_000_000 {
                    tsMs = Int64(tsRaw)
                } else {
                    tsMs = Int64(tsRaw * 1000.0)
                }
                local[tsMs] = v
            }

            if local.isEmpty { continue }

            if let detected {
                switch detected {
                case .wind: for (k,v) in local { windByTs[k] = v }
                case .gust: for (k,v) in local { gustByTs[k] = v }
                case .dir:  for (k,v) in local { dirByTs[k]  = v }
                }
            } else {
                anySeries.append((name: rawName, points: local))
            }
        }

        // si rien détecté : prend la série la plus fournie comme wind, la 2e comme gust
        if windByTs.isEmpty && gustByTs.isEmpty {
            let sorted = anySeries.sorted { $0.points.count > $1.points.count }
            if let first = sorted.first { windByTs = first.points }
            if sorted.count > 1 { gustByTs = sorted[1].points }
        }

        let allTs = Set(windByTs.keys).union(gustByTs.keys).union(dirByTs.keys).sorted()
        if allTs.isEmpty { throw WindServiceError.empty }

        var out: [WCWindObservation] = []
        out.reserveCapacity(allTs.count)

        for tsMs in allTs {
            let w = windByTs[tsMs]
            let g = gustByTs[tsMs]
            let d = dirByTs[tsMs]
            if w == nil && g == nil { continue }

            let tsSec = TimeInterval(tsMs) / 1000.0
            out.append(
                WCWindObservation(
                    ts: tsSec,
                    ws: WCWindSpeed(moy: WCScalar(w), max: WCScalar(g)),
                    wd: WCWindDir(moy: WCScalar(d))
                )
            )
        }

        if out.isEmpty { throw WindServiceError.empty }
        return out
    }

    /// Merge timestamps dupliqués
    private func mergeAndFilter(_ input: [WCWindObservation]) -> [WCWindObservation] {
        guard !input.isEmpty else { return [] }

        var byTs: [TimeInterval: WCWindObservation] = [:]

        for o in input {
            if var existing = byTs[o.ts] {
                let wM = existing.ws.moy.value ?? o.ws.moy.value
                let wG = existing.ws.max.value ?? o.ws.max.value
                let wD = existing.wd.moy.value ?? o.wd.moy.value

                existing = WCWindObservation(
                    ts: o.ts,
                    ws: WCWindSpeed(moy: WCScalar(wM), max: WCScalar(wG)),
                    wd: WCWindDir(moy: WCScalar(wD))
                )
                byTs[o.ts] = existing
            } else {
                byTs[o.ts] = o
            }
        }

        return byTs.values
            .filter { ($0.ws.moy.value != nil) || ($0.ws.max.value != nil) }
            .sorted { $0.ts < $1.ts }
    }

    // MARK: - Fallback Highcharts helpers

    private func findSeries(in json: Any) -> [[String: Any]] {
        if let dict = json as? [String: Any] {
            if let arr = dict["series"] as? [[String: Any]] { return arr }
            for (_, v) in dict {
                let found = findSeries(in: v)
                if !found.isEmpty { return found }
            }
        } else if let arr = json as? [Any] {
            for v in arr {
                let found = findSeries(in: v)
                if !found.isEmpty { return found }
            }
        }
        return []
    }

    private func extractPoints(from series: [String: Any]) -> [Any] {
        if let a = series["data"] as? [Any] { return a }
        if let a = series["points"] as? [Any] { return a }
        if let a = series["values"] as? [Any] { return a }

        if let d = series["data"] as? [String: Any] {
            if let a = d["data"] as? [Any] { return a }
            if let a = d["points"] as? [Any] { return a }
            if let a = d["values"] as? [Any] { return a }
        }

        for (_, v) in series {
            if let a = v as? [Any], looksLikePoints(a) { return a }
            if let d = v as? [String: Any] {
                for (_, vv) in d {
                    if let a = vv as? [Any], looksLikePoints(a) { return a }
                }
            }
        }
        return []
    }

    private func looksLikePoints(_ a: [Any]) -> Bool {
        guard let first = a.first else { return false }
        if let pair = first as? [Any], pair.count >= 2 {
            return toDouble(pair[0]) != nil && toDouble(pair[1]) != nil
        }
        if let dict = first as? [String: Any] {
            return (toDouble(dict["x"]) != nil || toDouble(dict["t"]) != nil || toDouble(dict["time"]) != nil)
                && (toDouble(dict["y"]) != nil || toDouble(dict["v"]) != nil || toDouble(dict["value"]) != nil)
        }
        return false
    }

    private enum SeriesKindOrDir { case wind, gust, dir }

    private func parsePoint(_ p: Any) -> (Double?, Double?) {
        if let arr = p as? [Any], arr.count >= 2 {
            return (toDouble(arr[0]), toDouble(arr[1]))
        }
        if let dict = p as? [String: Any] {
            let ts = toDouble(dict["x"] ?? dict["t"] ?? dict["time"] ?? dict["ts"])
            let v  = toDouble(dict["y"] ?? dict["v"] ?? dict["value"])
            return (ts, v)
        }
        return (nil, nil)
    }

    private func toDouble(_ any: Any?) -> Double? {
        guard let any else { return nil }
        if let n = any as? NSNumber { return n.doubleValue }
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String {
            return Double(s.replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }
}

// MARK: - Helpers used by WindViewModel

extension WindService {

    struct WindChartResult {
        let latest: WCWindObservation
        let samples: [WCChartSample]
    }

    static func fetchChartWC(sensorId: String, timeFrame: Int) async throws -> WindChartResult {
        let service = WindService()
        let observations = try await service.fetchSeries(sensorId: sensorId, timeFrameMinutes: timeFrame)

        guard let latest = observations.max(by: { $0.ts < $1.ts }) else {
            throw WindServiceError.empty
        }

        let samples: [WCChartSample] = observations
            .sorted(by: { $0.ts < $1.ts })
            .flatMap { obs -> [WCChartSample] in
                let date = Date(timeIntervalSince1970: obs.ts)
                let wind = obs.ws.moy.value ?? .nan
                let gust = obs.ws.max.value ?? .nan

                var out: [WCChartSample] = []
                if wind.isFinite {
                    out.append(WCChartSample(id: "\(Int(obs.ts))_wind", t: date, value: wind, kind: .wind))
                }
                if gust.isFinite {
                    out.append(WCChartSample(id: "\(Int(obs.ts))_gust", t: date, value: gust, kind: .gust))
                }
                return out
            }

        return WindChartResult(latest: latest, samples: samples)
    }

    static func fetchLatestWC(sensorId: String) async throws -> WCWindObservation {
        // Default to 2h so stations always have enough points; avoids empty series issues.
        let result = try await fetchChartWC(sensorId: sensorId, timeFrame: 60)
        return result.latest
    }
}
