import Foundation

final class GoWindHistoryStore {
    static let shared = GoWindHistoryStore()

    private let fm = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // Ajuste si tu veux : 24h
    private let retentionHours: Double = 24

    private init() {
        encoder.outputFormatting = [.withoutEscapingSlashes]
    }

    func append(stationId: String, measuredAt: Date, wind: Double?, gust: Double?, dir: Double?) {
        var arr = load(stationId: stationId)

        let sample = GoWindHistorySample(
            id: "\(Int(measuredAt.timeIntervalSince1970))",
            t: measuredAt,
            wind: wind,
            gust: gust,
            dir: dir
        )
        arr.append(sample)

        // nettoyage: ne garde que les X dernières heures
        let cutoff = Date().addingTimeInterval(-(retentionHours * 3600))
        arr.removeAll { $0.t < cutoff }

        // anti-doublons si refresh rapide (mêmes secondes)
        arr = dedupeBySecond(arr)

        save(stationId: stationId, samples: arr)
    }

    func load(stationId: String) -> [GoWindHistorySample] {
        guard let url = fileURL(stationId: stationId),
              fm.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let arr = try? decoder.decode([GoWindHistorySample].self, from: data)
        else { return [] }
        return arr
    }

    private func save(stationId: String, samples: [GoWindHistorySample]) {
        guard let url = fileURL(stationId: stationId),
              let data = try? encoder.encode(samples) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private func fileURL(stationId: String) -> URL? {
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("GoWindHistory", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("\(stationId).json")
    }

    private func dedupeBySecond(_ arr: [GoWindHistorySample]) -> [GoWindHistorySample] {
        var seen = Set<String>()
        var out: [GoWindHistorySample] = []
        out.reserveCapacity(arr.count)

        for s in arr.sorted(by: { $0.t < $1.t }) {
            let k = "\(Int(s.t.timeIntervalSince1970))"
            if seen.contains(k) { continue }
            seen.insert(k)
            out.append(s)
        }
        return out
    }
}
